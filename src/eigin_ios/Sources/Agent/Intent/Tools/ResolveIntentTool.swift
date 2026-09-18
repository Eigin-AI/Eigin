import Foundation

struct ResolveIntentTool: Tool {
    static let capability = ToolCapability(
        kind: .builtIn, key: "resolve_intent",
        displayName: Localized.Tools.Agent.resolveIntent,
        description: Localized.Tools.Description.resolveIntent,
        defaultPermissionLevel: .always, category: .agent
    )

    let name = "resolve_intent"
    var isSmallContext: Bool = false
    let intentService: any IntentService
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

    init(intentService: any IntentService = PreviewIntentService()) {
        self.intentService = intentService
    }

    func definition() -> ToolDefinition {
        ToolDefinition(
            name: name,
            description: "Mark an intent as resolved — you've fulfilled this goal or it's no longer relevant.",
            parameters: JSONSchema(
                type: "object",
                properties: [
                    "id": .init(
                        type: "string",
                        description: "The ID of the intent to resolve."
                    ),
                ],
                required: ["id"]
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
        guard let intentIDString = args["id"] as? String,
              let intentID = UUID(uuidString: intentIDString)
        else {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: ["Missing or invalid 'id' parameter"]),
                isError: true
            )
        }

        do {
            try await intentService.resolve(id: intentID)
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(result: [
                    "id": intentID.uuidString,
                    "action": "resolved",
                ]),
                isError: false
            )
        } catch {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: [error.localizedDescription]),
                isError: true
            )
        }
    }
}
