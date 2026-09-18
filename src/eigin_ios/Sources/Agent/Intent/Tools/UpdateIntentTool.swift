import Foundation

/// Edits an existing intent: revise its text, or replace its tasks, events, or
/// schedules. Use `list_intents` first to read the current ids, then send the
/// full desired state for any collection you want to change.
struct UpdateIntentTool: Tool {
    static let capability = ToolCapability(
        kind: .builtIn, key: "update_intent",
        displayName: Localized.Tools.Agent.updateIntent,
        description: Localized.Tools.Description.updateIntent,
        defaultPermissionLevel: .always, category: .agent
    )

    let name = "update_intent"
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
            description: "Update an existing intent. Pass only the fields you want to change. "
                + "Each of tasks, events, and schedules fully replaces the current list, so "
                + "read the intent with list_intents first and resend unchanged items (with "
                + "their id) alongside your edits — for example, to tick off a task, resend "
                + "the full task list with that item's `completed` set to true.",
            parameters: JSONSchema(
                type: "object",
                properties: [
                    "id": .init(type: "string", description: "The id of the intent to update."),
                    "content": .init(
                        type: "string",
                        description: "New description for the intent."
                    ),
                    "tasks": IntentToolSchema.tasks,
                    "events": IntentToolSchema.events,
                    "schedules": IntentToolSchema.schedules,
                ],
                required: ["id"]
            )
        )
    }

    @MainActor func execute(_ toolCall: ToolCall, agent _: Agent) async -> ToolResult {
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
            try await intentService.update(
                id: intentID,
                content: (args["content"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                tasks: IntentArguments.tasks(from: args["tasks"]),
                events: IntentArguments.events(from: args["events"]),
                schedules: IntentArguments.schedules(from: args["schedules"])
            )
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(result: [
                    "id": intentID.uuidString,
                    "action": "updated",
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
