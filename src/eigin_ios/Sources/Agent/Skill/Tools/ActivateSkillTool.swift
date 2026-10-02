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

    init(chatID: UUID? = nil) {
        self.chatID = chatID
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
            return await reactivate(skillID: skillID, context: context, chat: chat, toolCallID: id)
        }

        // Bundled and MCP server skills are checked directly (rather than
        // through ``SkillCatalog``, which would collapse the distinction)
        // because only MCP skills need a connection attempt before activating.
        if let skill = BundledSkill.skill(forID: skillID) {
            return activateBundled(skill, on: chat, toolCallID: id)
        }
        return await activateMCPServer(skillID: skillID, context: context, on: chat, toolCallID: id)
    }

    /// Idempotent re-activation: re-resolves the skill against currently
    /// connected providers and re-registers tools. Drops the entry when its
    /// capability is no longer connected, so a later activation can succeed.
    @MainActor private func reactivate(
        skillID: String,
        context: ModelContext,
        chat: Chat,
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
            let missing = missingCapabilities(of: skill, context: context)
            guard missing.isEmpty else {
                // Stale entry: the backing capability is gone. Drop it so a
                // later activation isn't blocked, and tell the agent why.
                chat.activeSkillEntries.removeAll { $0.skillID == skillID }
                let names = missing.map(\.displayName).sorted().joined(separator: ", ")
                return ToolResult(
                    toolCallID: id,
                    content: ToolHelpers.output(errors: [
                        "Skill '\(skillID)' was active but no connected provider supplies \(names) anymore. Connect one in Settings, then activate again.",
                    ]),
                    isError: true
                )
            }
            SkillActivation.activate(
                skillID: skill.id,
                on: chat,
                activatingToolCallID: id
            )
            return activationResult(skill: skill, toolCallID: id)
        }
        // MCP-backed skill: reconnects before re-activating, healing a
        // dropped server connection.
        return await activateMCPServer(skillID: skillID, context: context, on: chat, toolCallID: id)
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
        return skill.requiredCapabilities.subtracting(connected)
    }

    /// The shared success payload for (re)activating a bundled skill.
    @MainActor private func activationResult(skill: Skill, toolCallID id: String) -> ToolResult {
        ToolResult(
            toolCallID: id,
            content: ToolHelpers.output(result: [
                "activated": skill.id,
                "tools_available": skill.requiredTools.map(\.key).sorted(),
                // Included inline so the model has it this turn — the Gatekeeper's
                // per-turn hint (which also carries this instruction on every
                // subsequent turn) isn't recomputed mid-turn after a tool call.
                "instruction": skill.instruction,
            ]),
            isError: false
        )
    }

    // MARK: - Bundled skills

    @MainActor private func activateBundled(
        _ skill: Skill,
        on chat: Chat,
        toolCallID id: String
    ) -> ToolResult {
        if skill.alwaysActive {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: ["Skill '\(skill.id)' is always active"]),
                isError: true
            )
        }
        SkillActivation.activate(
            skillID: skill.id,
            on: chat,
            activatingToolCallID: id
        )
        return activationResult(skill: skill, toolCallID: id)
    }

    // MARK: - MCP server skills

    /// Connects the server backing `skillID` before activating, so activation
    /// either succeeds with tools available or fails with an actionable error
    /// the agent can relay to the user (e.g. "reauthorize in Settings").
    @MainActor private func activateMCPServer(
        skillID: String,
        context: ModelContext,
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

        return ToolResult(
            toolCallID: id,
            content: ToolHelpers.output(result: [
                "activated": skillID,
                "tools_available": skill.requiredTools.map(\.key).sorted(),
                "instruction": skill.instruction,
            ]),
            isError: false
        )
    }
}
