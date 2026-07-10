import Factory
import Foundation
import SwiftData

struct ActivateSkillTool: Tool {
    static let capability = ToolCapability(
        kind: .builtIn, key: "activate_skill",
        displayName: Localized.Tools.Agent.activateSkill,
        defaultPermissionLevel: .always, category: .agent
    )

    let name = "activate_skill"
    var displayName: String {
        Self.capability.displayName
    }

    var capabilities: [ToolCapability] {
        [Self.capability]
    }

    var category: ToolCapability.Category {
        .agent
    }

    var defaultPermissionLevel: ToolPermissionLevel {
        .always
    }

    private let chatID: UUID?
    let isSmallContext: Bool

    init(chatID: UUID? = nil, isSmallContext: Bool = false) {
        self.chatID = chatID
        self.isSmallContext = isSmallContext
    }

    func definition() -> ToolDefinition {
        let skills = isSmallContext
            ? BundledSkill.all
            : BundledSkill.all.filter { !$0.alwaysActive }
        let skillIDs = skills.map(\.id)
        let description = isSmallContext
            ? "Activate a skill to load its instructions and tools."
            : "Activate a skill to load its instructions and tools. Available skills: \(skillIDs.joined(separator: ", "))."
        return ToolDefinition(
            name: name,
            description: description,
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
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: ["Skill '\(skillID)' is already active"]),
                isError: true
            )
        }

        // Bundled and MCP server skills are checked directly (rather than
        // through ``SkillCatalog``, which would collapse the distinction)
        // because only MCP skills need a connection attempt before activating.
        if let skill = BundledSkill.skill(forID: skillID) {
            return activateBundled(skill, on: chat, toolCallID: id)
        }
        return await activateMCPServer(skillID: skillID, context: context, on: chat, toolCallID: id)
    }

    // MARK: - Bundled skills

    @MainActor private func activateBundled(
        _ skill: Skill,
        on chat: Chat,
        toolCallID id: String
    ) -> ToolResult {
        if skill.alwaysActive, !isSmallContext {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: ["Skill '\(skill.id)' is always active"]),
                isError: true
            )
        }
        SkillActivation.activate(
            skillID: skill.id,
            on: chat,
            activatingToolCallID: id,
            isSmallContext: isSmallContext
        )
        return ToolResult(
            toolCallID: id,
            content: ToolHelpers.output(result: [
                "activated": skill.id,
                "tools_available": skill.requiredTools.map(\.key).sorted(),
                // Included inline so the model has it this turn — the Gatekeeper's
                // per-turn hint (which also carries this instruction on every
                // subsequent turn) isn't recomputed mid-turn after a tool call.
                "instruction": isSmallContext ? skill.smallInstruction : skill.instruction,
            ]),
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
            activatingToolCallID: id,
            isSmallContext: isSmallContext
        )

        return ToolResult(
            toolCallID: id,
            content: ToolHelpers.output(result: [
                "activated": skillID,
                "tools_available": skill.requiredTools.map(\.key).sorted(),
                "instruction": isSmallContext ? skill.smallInstruction : skill.instruction,
            ]),
            isError: false
        )
    }
}
