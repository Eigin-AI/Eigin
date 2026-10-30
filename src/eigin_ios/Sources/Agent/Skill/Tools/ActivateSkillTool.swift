import Factory
import Foundation
import SwiftData

struct ActivateSkillTool: Tool {
    static let capability = ToolCapability(
        kind: .builtIn, key: "activate_skill",
        displayName: Localized.Tools.Agent.activateSkill,
        description: Localized.Tools.Description.activateSkill,
        defaultPermissionLevel: .always, category: .skills, isUserConfigurable: false
    )

    let name = "activate_skill"
    var displayName: String {
        Self.capability.displayName
    }

    var capabilities: [ToolCapability] {
        [Self.capability]
    }

    var category: ToolCapability.Category {
        .skills
    }

    var defaultPermissionLevel: ToolPermissionLevel {
        .always
    }

    private let chatID: UUID?
    private let onConnectCapability: ConnectCapabilityHandler?
    private let capabilityDeclines: DeclinedCapabilities

    private let connectionGate: SkillConnectionGate?
    private let userMessageID: String?

    @MainActor init(
        chatID: UUID? = nil,
        onConnectCapability: ConnectCapabilityHandler? = nil,
        capabilityDeclines: DeclinedCapabilities = DeclinedCapabilities(),
        connectionGate: SkillConnectionGate? = nil,
        userMessageID: String? = nil
    ) {
        self.connectionGate = connectionGate
        self.userMessageID = userMessageID
        self.chatID = chatID
        self.onConnectCapability = onConnectCapability
        self.capabilityDeclines = capabilityDeclines
    }

    func definition() -> ToolDefinition {
        ToolDefinition(
            name: name,
            description: "Activate a skill by ID to load its instructions and tools. Use `search_skills` or the skills hinted in your system hint to find IDs.",
            parameters: JSONSchema(
                type: "object",
                properties: [
                    "skill_id": .init(
                        type: "string",
                        description: "The ID of the skill to activate."
                    ),
                ],
                required: ["skill_id"]
            )
        )
    }

    @MainActor func execute(_ toolCall: ToolCall, agent: Agent) async -> ToolResult {
        let id = toolCall.id

        guard let args = ToolHelpers.parseArguments(toolCall.function.arguments) else {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: ["Invalid JSON arguments"]),
                isError: true
            )
        }
        guard let skillID = args["skill_id"] as? String else {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: ["Missing 'skill_id' parameter"]),
                isError: true
            )
        }

        guard let chatID, let context = agent.modelContext else {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: ["No chat context available"]),
                isError: true
            )
        }

        let targetChatID = chatID
        var descriptor = FetchDescriptor<Chat>(
            predicate: #Predicate { $0.id == targetChatID }
        )
        descriptor.fetchLimit = 1

        guard let chat = (try? context.fetch(descriptor))?.first else {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: ["Chat not found"]),
                isError: true
            )
        }

        if chat.isSkillActive(skillID) {
            return await reactivate(
                skillID: skillID,
                context: context,
                chat: chat,
                agent: agent,
                toolCallID: id
            )
        }

        // Bundled and MCP server skills are checked directly (rather than
        // through ``SkillCatalog``, which would collapse the distinction)
        // because only MCP skills need a connection attempt before activating.
        if let skill = BundledSkill.skill(forID: skillID) {
            return await activateBundled(
                skill,
                on: chat,
                agent: agent,
                context: context,
                toolCallID: id
            )
        }
        return await activateMCPServer(
            skillID: skillID, context: context, agent: agent, on: chat, toolCallID: id
        )
    }

    /// Idempotent re-activation: re-resolves the skill against currently
    /// connected providers and re-registers tools. When its capability is no
    /// longer connected, activates afresh, which asks to connect it.
    @MainActor private func reactivate(
        skillID: String,
        context: ModelContext,
        chat: Chat,
        agent: Agent,
        toolCallID id: String
    ) async -> ToolResult {
        if let skill = BundledSkill.skill(forID: skillID) {
            if skill.alwaysActive {
                return ToolResult(
                    toolCallID: id,
                    content: ToolHelpers.output(errors: ["Skill '\(skill.id)' is always active"]),
                    isError: true
                )
            }
            guard missingCapabilities(of: skill, context: context).isEmpty else {
                // Stale entry: the backing capability is gone. Drop it and
                // activate afresh, which asks to connect it like the first time.
                chat.activeSkillEntries.removeAll { $0.skillID == skillID }
                return await activateBundled(
                    skill,
                    on: chat,
                    agent: agent,
                    context: context,
                    toolCallID: id
                )
            }
            connectionGate?.clear(chatID: chat.id, skillID: skill.id)
            SkillActivation.activate(
                skillID: skill.id,
                on: chat,
                activatingToolCallID: id
            )
            return activationResult(skill: skill, agent: agent, context: context, toolCallID: id)
        }
        // MCP-backed skill: reconnects before re-activating, healing a
        // dropped server connection.
        return await activateMCPServer(
            skillID: skillID, context: context, agent: agent, on: chat, toolCallID: id
        )
    }

    /// Capabilities the skill needs that no connected, enabled integration
    /// currently provides.
    @MainActor private func missingCapabilities(
        of skill: Skill,
        context: ModelContext
    ) -> Set<Capability> {
        guard !skill.requiredCapabilities.isEmpty else { return [] }
        let integrations = ((try? context.fetch(FetchDescriptor<Integration>())) ?? [])
            .filter(\.isEnabled)
        let connected = Container.shared.integrationManager()
            .connectedCapabilities(integrations: integrations)
        return SkillCatalog.missingCapabilities(of: skill, connected: connected)
    }

    /// The shared success payload for (re)activating a skill — bundled or MCP.
    /// `instruction` is included inline so the model has it this turn: the
    /// Gatekeeper's per-turn hint (which also carries it on every subsequent
    /// turn) isn't recomputed mid-turn after a tool call.
    @MainActor private func activationResult(
        skill: Skill,
        agent: Agent,
        context: ModelContext,
        toolCallID id: String
    ) -> ToolResult {
        ToolResult(
            toolCallID: id,
            content: ToolHelpers.output(result: [
                "activated": skill.id,
                "tools_available": availableToolKeys(skill: skill, agent: agent, context: context),
                "instruction": skill.instruction,
            ]),
            isError: false
        )
    }

    /// The tool keys activating this skill actually puts in the registry: its
    /// required tools plus the tools of the integrations now serving its
    /// capabilities, minus anything the user's permission policy excludes.
    /// Capability-gated skills (calendar, health, …) have no `requiredTools`,
    /// so the integration tools here are the whole story.
    @MainActor private func availableToolKeys(
        skill: Skill,
        agent: Agent,
        context: ModelContext
    ) -> [String] {
        var keys = Set(skill.requiredTools.map(\.key))
        let capabilities = skill.requiredCapabilities.union(skill.optionalCapabilities)
        if !capabilities.isEmpty {
            let integrations = ((try? context.fetch(FetchDescriptor<Integration>())) ?? [])
                .filter(\.isEnabled)
            let selections =
                ((try? context.fetch(FetchDescriptor<CapabilityProviderSelection>())) ?? [])
            let toolContext = ToolContext(chatID: chatID, agentID: agent.id)
            let tools = Container.shared.integrationManager().toolsByCapability(
                integrations: integrations,
                selections: selections,
                context: toolContext
            )
            for capability in capabilities {
                keys.formUnion((tools[capability] ?? []).map(\.name))
            }
        }
        let policy = PermissionPolicyLoader.load(
            for: agent, chatID: chatID, modelContext: context
        )
        return keys.filter { policy.permissionLevel(for: $0) != .never }.sorted()
    }

    // MARK: - Bundled skills

    @MainActor private func activateBundled(
        _ skill: Skill,
        on chat: Chat,
        agent: Agent,
        context: ModelContext,
        toolCallID id: String
    ) async -> ToolResult {
        if skill.alwaysActive {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: ["Skill '\(skill.id)' is always active"]),
                isError: true
            )
        }
        let missing = missingCapabilities(of: skill, context: context)
        if !missing.isEmpty,
           let unconnected = await connect(
               missing,
               skillID: skill.id,
               agent: agent,
               context: context,
               toolCallID: id
           )
        {
            return unconnected
        }
        connectionGate?.clear(chatID: chat.id, skillID: skill.id)
        SkillActivation.activate(
            skillID: skill.id,
            on: chat,
            activatingToolCallID: id
        )
        return activationResult(skill: skill, agent: agent, context: context, toolCallID: id)
    }

    // MARK: - Connecting what a skill needs

    /// Asks the person to connect what a skill needs, once. Returns `nil` when
    /// it is now connected, or what to tell the agent when it isn't. None of
    /// these are errors: a no is an answer, and the agent carries on without.
    @MainActor private func connect(
        _ missing: Set<Capability>,
        skillID: String,
        agent: Agent,
        context: ModelContext,
        toolCallID id: String
    ) async -> ToolResult? {
        let providers = SkillCatalog.providers(for: missing)
        // Within a capability any provider is enough ("or"); a skill needs
        // all of its capabilities ("and").
        let names = SkillCatalog.providerNames(for: missing)

        if missing.allSatisfy(capabilityDeclines.isDeclined) {
            return notConnected(
                "The user declined to connect \(names). Don't activate this skill again; if it would help, tell them they can add it in Settings → Connections.",
                toolCallID: id
            )
        }
        guard let onConnectCapability else {
            return notConnected(
                "Using this skill needs \(names) connected, and the user can't be asked right now. Answer without it; they can add it in Settings → Connections.",
                toolCallID: id
            )
        }
        if await isRefusedByIOS(providers) {
            return notConnected(
                "iOS has \(names) turned off for Eigin, so it can't be connected. Answer without it, and tell them they can allow Eigin in the iOS Settings app, then add it in this app's Settings → Connections.",
                toolCallID: id
            )
        }

        guard let chatID, let connectionGate else {
            return notConnected(
                Prompt.Skills.connectionUnavailable,
                toolCallID: id
            )
        }
        let attempt: UUID
        switch connectionGate.request(
            chatID: chatID,
            skillID: skillID,
            missing: missing,
            messageID: userMessageID
        ) {
        case .askUser, .waitForUser:
            return confirmationRequired(missing, names: names, toolCallID: id)
        case .connect(let reservation):
            attempt = reservation
        }
        defer { connectionGate.finish(chatID: chatID, skillID: skillID, attempt: attempt) }
        guard !Task.isCancelled else {
            return notConnected(
                Prompt.Skills.connectionCancelled(connections: names),
                toolCallID: id
            )
        }
        let request = CapabilityRequest(
            capabilities: missing,
            providerIDs: providers.map(\.id),
            agentName: agent.name
        )
        return await connectionOutcome(
            onConnectCapability(request), missing: missing, names: names,
            context: context, toolCallID: id
        )
    }

    @MainActor private func confirmationRequired(
        _ missing: Set<Capability>, names: String, toolCallID id: String
    ) -> ToolResult {
        ToolResult(
            toolCallID: id,
            content: ToolHelpers.output(result: [
                "activated": false,
                "status": "confirmation_required",
                "capabilities": missing.map(\.rawValue).sorted(),
                "reason": Prompt.Skills.connectionConfirmation(connections: names),
            ]),
            isError: false
        )
    }

    @MainActor private func connectionOutcome(
        _ outcome: CapabilityConnectResult,
        missing: Set<Capability>, names: String,
        context: ModelContext, toolCallID id: String
    ) -> ToolResult? {
        switch outcome {
        case .connected:
            missing.forEach(capabilityDeclines.clear)
            // Verify every requested capability before activating.
            if let remaining = notConnectedAfterConnect(missing, context: context) {
                return notConnected(
                    Prompt.Skills.connectionIncomplete(connections: remaining),
                    toolCallID: id
                )
            }
            return nil
        case .declined:
            missing.forEach(capabilityDeclines.decline)
            return notConnected(
                "The user chose not to connect \(names). Don't activate this skill again; answer without it. If it would help later, they can add it in Settings → Connections.",
                toolCallID: id
            )
        case .cancelled:
            return notConnected(
                Prompt.Skills.connectionCancelled(connections: names),
                toolCallID: id
            )
        }
    }

    /// Capabilities from the request that no integration ended up
    /// connecting — the sheet lets the person stop after one of several.
    @MainActor private func notConnectedAfterConnect(
        _ missing: Set<Capability>,
        context: ModelContext
    ) -> String? {
        let integrations = ((try? context.fetch(FetchDescriptor<Integration>())) ?? [])
            .filter(\.isEnabled)
        let connected = Container.shared.integrationManager()
            .connectedCapabilities(integrations: integrations)
        let remaining = missing.subtracting(connected)
        guard !remaining.isEmpty else { return nil }
        return ListFormatter.localizedString(byJoining: remaining.map(\.displayName))
    }

    /// Whether iOS has already refused every provider, so there is nothing
    /// left to ask. Only platform integrations can be refused like this.
    @MainActor private func isRefusedByIOS(_ providers: [IntegrationType]) async -> Bool {
        for provider in providers {
            guard let source = provider.authKind.platform,
                  await source.permission().access() == .refused
            else { return false }
        }
        return !providers.isEmpty
    }

    @MainActor private func notConnected(_ reason: String, toolCallID id: String) -> ToolResult {
        ToolResult(
            toolCallID: id,
            content: ToolHelpers.output(result: ["activated": false, "reason": reason]),
            isError: false
        )
    }

    // MARK: - MCP server skills

    /// Connects the server backing `skillID` before activating, so activation
    /// either succeeds with tools available or fails with an actionable error
    /// the agent can relay to the user (e.g. "reauthorize in Settings").
    @MainActor private func activateMCPServer(
        skillID: String,
        context: ModelContext,
        agent: Agent,
        on chat: Chat,
        toolCallID id: String
    ) async -> ToolResult {
        let servers = (try? context.fetch(FetchDescriptor<MCPServer>())) ?? []
        // `MCPServer` is a SwiftData model (a class), so the compiler treats
        // it as unsafe to pass into the `connect` actor hop below even though
        // this whole method runs on @MainActor throughout — `nonisolated(unsafe)`
        // tells it that's intentional. The `guard` has to bind a second
        // `nonisolated(unsafe)` local because unwrapping an optional otherwise
        // drops the annotation.
        nonisolated(unsafe) let matchedServer = MCPServerSkill.server(
            forSkillID: skillID,
            servers: servers
        )
        guard matchedServer != nil else {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: ["Unknown skill '\(skillID)'"]),
                isError: true
            )
        }
        nonisolated(unsafe) let server = matchedServer!

        let mcpServerManager = Container.shared.mcpServerManager()
        if let connectionError = await mcpServerManager.connect(server: server) {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: [
                    "Couldn't connect to '\(server.name)': \(connectionError). The user may need to reauthorize it in Settings.",
                ]),
                isError: true
            )
        }

        // Reproject: `connect` just refreshed cachedToolNames/serverInstructions.
        guard let skill = MCPServerSkill.skill(forID: skillID, servers: servers) else {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: ["Unknown skill '\(skillID)'"]),
                isError: true
            )
        }

        SkillActivation.activate(
            skillID: skillID,
            on: chat,
            activatingToolCallID: id
        )

        return activationResult(skill: skill, agent: agent, context: context, toolCallID: id)
    }
}
