import Foundation
import SwiftData

/// Starts a staged flow declared in a skill's `flows.toml` manifest.
///
/// Activation is expected to happen first, via ``ActivateSkillTool``: a
/// skill's instructions name the flow ids it owns. As a fallback — if the
/// model already knows a flow id from elsewhere and the owning skill isn't
/// active yet — this activates it so the call still succeeds.
struct StartFlowTool: Tool {
    static let capability = ToolCapability(
        kind: .builtIn, key: "start_flow",
        displayName: Localized.Tools.Agent.startFlow,
        description: Localized.Tools.Description.startFlow,
        defaultPermissionLevel: .always, category: .skills, isUserConfigurable: false
    )

    let name = "start_flow"
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
            Start a staged flow by id, as named in the currently active skill's instructions. \
            Returns the first stage's instructions — follow them, and call advance_flow when \
            you're ready to move on.
            """,
            parameters: JSONSchema(
                type: "object",
                properties: [
                    "flow": .init(
                        type: "string",
                        description: "The flow id to start."
                    ),
                ],
                required: ["flow"]
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
        guard let flowID = args["flow"] as? String else {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: ["Missing 'flow' parameter"]),
                isError: true
            )
        }
        guard let flow = FlowRegistry.all[flowID], let firstStage = flow.stages.first else {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: [
                    "Unknown flow '\(flowID)'. Flow ids are named in the instructions of the skill that owns them.",
                ]),
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

        if !chat.isSkillActive(flow.skillID) {
            SkillActivation.activate(
                skillID: flow.skillID,
                on: chat,
                activatingToolCallID: id,
                isSmallContext: isSmallContext
            )
        }

        // Overwrites any flow already in progress: starting a new one abandons the old.
        chat.activeFlow = FlowState(flowID: flowID, skillID: flow.skillID, stage: 0, notes: [])

        return ToolResult(
            toolCallID: id,
            content: ToolHelpers.output(result: [
                "flow": flowID,
                "stage": firstStage.name,
                "instructions": firstStage.instructions(notes: []),
            ]),
            isError: false
        )
    }
}
