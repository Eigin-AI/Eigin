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
        if isSmallContext {
            return ToolDefinition(
                name: name,
                description: "Activate a skill for its tools.",
                parameters: JSONSchema(
                    type: "object",
                    properties: [
                        "skill_id": .init(
                            type: "string",
                            description: "Skill to activate.",
                            enum: skillIDs
                        ),
                    ],
                    required: ["skill_id"]
                )
            )
        }
        return ToolDefinition(
            name: name,
            description: "Activate a skill to gain access to its tools. Available skills: \(skillIDs.joined(separator: ", ")).",
            parameters: JSONSchema(
                type: "object",
                properties: [
                    "skill_id": .init(
                        type: "string",
                        description: "The ID of the skill to activate.",
                        enum: skillIDs
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
        guard let skill = BundledSkill.skill(forID: skillID) else {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: ["Unknown skill '\(skillID)'"]),
                isError: true
            )
        }
        // In small context mode, always-active skills don't have their tools
        // loaded by default, so the model can activate them like any other skill.
        if skill.alwaysActive, !isSmallContext {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: ["Skill '\(skillID)' is always active"]),
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

        SkillActivation.activate(
            skillID: skillID,
            on: chat,
            activatingToolCallID: id,
            isSmallContext: isSmallContext
        )

        let toolNames = skill.requiredTools.map(\.key).sorted()
        return ToolResult(
            toolCallID: id,
            content: ToolHelpers.output(result: [
                "activated": skillID,
                "tools_available": toolNames,
                // Included inline so the model has it this turn — the Gatekeeper's
                // per-turn hint (which also carries this instruction on every
                // subsequent turn) isn't recomputed mid-turn after a tool call.
                "instruction": isSmallContext ? skill.smallInstruction : skill.instruction,
            ]),
            isError: false
        )
    }
}
