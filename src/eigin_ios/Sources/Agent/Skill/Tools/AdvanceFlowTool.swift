import Foundation
import SwiftData

/// Advances the active flow (started via ``StartFlowTool``) to its next stage.
struct AdvanceFlowTool: Tool {
    static let capability = ToolCapability(
        kind: .builtIn, key: "advance_flow",
        displayName: Localized.Tools.Agent.advanceFlow,
        defaultPermissionLevel: .always, category: .skills, isUserConfigurable: false
    )

    let name = "advance_flow"
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
    var isSmallContext: Bool = false

    init(chatID: UUID? = nil, isSmallContext: Bool = false) {
        self.chatID = chatID
        self.isSmallContext = isSmallContext
    }

    func definition() -> ToolDefinition {
        ToolDefinition(
            name: name,
            description: """
            Move the active flow to its next stage. Returns the next stage's instructions, \
            or a closing note once every stage is done.
            """,
            parameters: JSONSchema(
                type: "object",
                properties: [
                    "notes": .init(
                        type: "string",
                        description: "A short recap of what you learned or decided at this stage, to carry forward. Optional."
                    ),
                ]
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
        let notes = args["notes"] as? String

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

        guard var state = chat.activeFlow, let flow = FlowRegistry.all[state.flowID] else {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers
                    .output(errors: [Self.noActiveFlowError(activeSkillIDs: chat.activeSkillIDs)]),
                isError: true
            )
        }

        if let notes, !notes.isEmpty {
            state.notes.append(notes)
        }
        state.stage += 1

        guard state.stage < flow.stages.count else {
            chat.activeFlow = nil
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(result: [
                    "flow": state.flowID,
                    "status": "complete",
                    "instructions": "You've worked through every stage of this flow.",
                ]),
                isError: false
            )
        }

        let stage = flow.stages[state.stage]
        chat.activeFlow = state

        let instructions = stage.instructions(notes: state.notes)

        return ToolResult(
            toolCallID: id,
            content: ToolHelpers.output(result: [
                "flow": state.flowID,
                "stage": stage.name,
                "instructions": instructions,
            ]),
            isError: false
        )
    }

    private static func noActiveFlowError(activeSkillIDs: [String]) -> String {
        let available = FlowRegistry.all.values
            .filter { activeSkillIDs.contains($0.skillID) }
            .map(\.name)
            .sorted()
        if available.isEmpty {
            return "No flow is active. Call start_flow with a flow id named in the currently active skill's instructions."
        }
        return "No flow is active. Call start_flow with one of: \(available.joined(separator: ", "))."
    }
}
