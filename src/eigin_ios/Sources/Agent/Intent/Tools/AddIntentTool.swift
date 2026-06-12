import Foundation

/// Creates a new intent — a goal the agent will pursue until it resolves it.
/// Optionally seeds the intent with tasks, events, and schedules.
struct AddIntentTool: Tool {
    static let capability = ToolCapability(
        kind: .builtIn, key: "add_intent",
        displayName: Localized.Tools.Agent.addIntent,
        defaultPermissionLevel: .always, category: .agent
    )

    let name = "add_intent"
    var isSmallContext: Bool = false
    let intentService: any IntentService
    let spaceID: UUID?
    let chatID: UUID?
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

    init(
        intentService: any IntentService = PreviewIntentService(),
        spaceID: UUID? = nil,
        chatID: UUID? = nil
    ) {
        self.intentService = intentService
        self.spaceID = spaceID
        self.chatID = chatID
    }

    func definition() -> ToolDefinition {
        if isSmallContext {
            return ToolDefinition(
                name: name,
                description: "Set a goal for yourself.",
                parameters: JSONSchema(
                    type: "object",
                    properties: [
                        "content": .init(type: "string", description: "Goal description."),
                    ],
                    required: ["content"]
                )
            )
        }
        return ToolDefinition(
            name: name,
            description: "Set a new goal for yourself based on what the user needs. Intents "
                + "guide how you help across conversations and persist until you resolve them. "
                + "Optionally attach tasks to track, events to tie it to a date, or schedules "
                + "to make it recur.",
            parameters: JSONSchema(
                type: "object",
                properties: [
                    "content": .init(
                        type: "string",
                        description: "Natural language description of the intent."
                    ),
                    "tasks": IntentToolSchema.tasks,
                    "events": IntentToolSchema.events,
                    "schedules": IntentToolSchema.schedules,
                ],
                required: ["content"]
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

        guard let content = args["content"] as? String, !content.isEmpty else {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: ["'content' is required"]),
                isError: true
            )
        }

        do {
            let newID = try await intentService.create(
                content: content,
                agentID: agent.id,
                spaceID: spaceID,
                chatID: chatID,
                tasks: IntentArguments.tasks(from: args["tasks"]) ?? [],
                events: IntentArguments.events(from: args["events"]) ?? [],
                schedules: IntentArguments.schedules(from: args["schedules"]) ?? []
            )
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(result: ["id": newID.uuidString, "action": "created"]),
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
