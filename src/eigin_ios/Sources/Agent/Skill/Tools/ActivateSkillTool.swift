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

    private let skillSession: SkillSession?
    private let chatID: UUID?
    private let onConnectCapability: ConnectCapabilityHandler?
    private let capabilityDeclines: DeclinedCapabilities

    private let connectionGate: SkillConnectionGate?
    private let userMessageID: String?

    @MainActor init(
        chatID: UUID? = nil,
        skillSession: SkillSession? = nil,
        onConnectCapability: ConnectCapabilityHandler? = nil,
        capabilityDeclines: DeclinedCapabilities = DeclinedCapabilities(),
        connectionGate: SkillConnectionGate? = nil,
        userMessageID: String? = nil
    ) {
        self.connectionGate = connectionGate
        self.userMessageID = userMessageID
        self.chatID = chatID
        self.skillSession = skillSession
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

        let session = skillSession ?? SkillSession(
            chatID: chatID,
            permissionPolicy: agent.modelContext.map {
                PermissionPolicyLoader.load(for: agent, chatID: chatID, modelContext: $0)
            } ?? AlwaysAllowPolicy(),
            accessPolicy: SpaceAccessPolicy(currentSpaceID: nil, publicSpaceIDs: []),
            agentID: agent.id,
            connectionRequest: SkillConnectionRequest(
                chatID: chatID, onConnectCapability: onConnectCapability,
                capabilityDeclines: capabilityDeclines, connectionGate: connectionGate,
                userMessageID: userMessageID
            )
        )
        return await session.activate(skillID: skillID, agent: agent, toolCallID: id)
    }
}
