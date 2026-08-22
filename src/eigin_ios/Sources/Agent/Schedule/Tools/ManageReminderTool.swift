import Foundation

struct ManageReminderTool: Tool {
    static let capability = ToolCapability(
        kind: .builtIn, key: "manage_reminder",
        displayName: Localized.Tools.Schedule.manageReminder,
        defaultPermissionLevel: .ask, category: .system
    )

    let name = "manage_reminder"
    var isSmallContext: Bool = false
    let reminderService: (any ReminderService)?
    let canPromptUser: Bool
    var displayName: String {
        Self.capability.displayName
    }

    var capabilities: [ToolCapability] {
        [Self.capability]
    }

    var category: ToolCapability.Category {
        .system
    }

    var defaultPermissionLevel: ToolPermissionLevel {
        .ask
    }

    func definition() -> ToolDefinition {
        if isSmallContext {
            return ToolDefinition(
                name: name,
                description: "Create, update, complete, or delete a reminder.",
                parameters: JSONSchema(
                    type: "object",
                    properties: [
                        "action": .init(
                            type: "string",
                            description: "Action.",
                            enum: ["create", "update", "complete", "delete"]
                        ),
                        "title": .init(type: "string", description: "Reminder title."),
                        "reminder_id": .init(type: "string", description: "Reminder ID."),
                    ],
                    required: ["action"]
                )
            )
        }
        return ToolDefinition(
            name: name,
            description: "Create, update, complete, or delete a reminder.",
            parameters: JSONSchema(
                type: "object",
                properties: [
                    "action": .init(
                        type: "string",
                        description: "Action to perform.",
                        enum: ["create", "update", "complete", "delete"]
                    ),
                    "reminder_id": .init(
                        type: "string",
                        description: "Reminder ID (required for update, complete, delete)."
                    ),
                    "title": .init(
                        type: "string",
                        description: "Reminder title (required for create)."
                    ),
                    "list_id": .init(
                        type: "string",
                        description: "Target reminder list ID (for create). Omit for default list."
                    ),
                    "due_date": .init(
                        type: "string",
                        description: "Due date/time (e.g. \"2026-03-27 08:00\")."
                    ),
                    "notes": .init(
                        type: "string",
                        description: "Reminder notes."
                    ),
                    "priority": .init(
                        type: "integer",
                        description: "Priority: 0 = none, 1 = high, 5 = medium, 9 = low."
                    ),
                ],
                required: ["action"]
            )
        )
    }

    func disclosure(for toolCall: ToolCall) -> ToolDisclosure? {
        guard let action = ToolHelpers.stringArgument(toolCall, "action") else { return nil }
        let phrase: String
        switch action {
        case "create": phrase = Localized.Permission.Disclosure.reminderAdd
        case "update": phrase = Localized.Permission.Disclosure.reminderUpdate
        case "complete": phrase = Localized.Permission.Disclosure.reminderComplete
        case "delete": phrase = Localized.Permission.Disclosure.reminderRemove
        default: return nil
        }
        let title = ToolHelpers.stringArgument(toolCall, "title")
        var due: String?
        if let dueString = ToolHelpers.stringArgument(toolCall, "due_date"),
           let date = LocalDateFormatter.parse(dueString)
        {
            due = Localized.Permission.Disclosure.due(LocalDateFormatter.string(from: date))
        }

        let summary: String? = switch (title, due) {
        case (let title?, let due?): "\(title) (\(due))"
        case (let title?, nil): title
        case (nil, let due?): due
        case (nil, nil): nil
        }
        return ToolDisclosure(actionPhrase: phrase, detail: summary.map { .inline($0) })
    }

    @MainActor func execute(_ toolCall: ToolCall, agent: Agent) async -> ToolResult {
        let id = toolCall.id

        guard let service = reminderService else {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: ["Reminder service unavailable."]),
                isError: true
            )
        }

        let auth = await service.authorize(canPromptUser: canPromptUser)
        if case .denied(let reason) = auth {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: [reason]),
                isError: true
            )
        }

        guard let args = ToolHelpers.parseArguments(toolCall.function.arguments) else {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: ["Invalid JSON arguments."]),
                isError: true
            )
        }

        guard let action = args["action"] as? String else {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: ["Missing 'action'."]),
                isError: true
            )
        }

        do {
            switch action {
            case "create":
                guard let title = args["title"] as? String else {
                    return ToolResult(
                        toolCallID: id,
                        content: ToolHelpers.output(errors: ["Missing 'title' for create."]),
                        isError: true
                    )
                }
                let newReminder = NewReminder(
                    title: title,
                    listID: args["list_id"] as? String,
                    dueDate: (args["due_date"] as? String).flatMap { LocalDateFormatter.parse($0) },
                    notes: args["notes"] as? String,
                    priority: args["priority"] as? Int
                )
                let reminderID = try await service.createReminder(newReminder)
                return ToolResult(
                    toolCallID: id,
                    content: ToolHelpers.output(result: [
                        "status": "created",
                        "reminder_id": reminderID,
                        "title": title,
                    ]),
                    isError: false
                )

            case "update":
                guard let reminderID = args["reminder_id"] as? String else {
                    return ToolResult(
                        toolCallID: id,
                        content: ToolHelpers.output(errors: ["Missing 'reminder_id' for update."]),
                        isError: true
                    )
                }
                let changes = ReminderChanges(
                    title: args["title"] as? String,
                    dueDate: (args["due_date"] as? String).flatMap { LocalDateFormatter.parse($0) },
                    notes: args["notes"] as? String,
                    priority: args["priority"] as? Int
                )
                try await service.updateReminder(id: reminderID, changes: changes)
                return ToolResult(
                    toolCallID: id,
                    content: ToolHelpers.output(result: [
                        "status": "updated",
                        "reminder_id": reminderID,
                    ]),
                    isError: false
                )

            case "complete":
                guard let reminderID = args["reminder_id"] as? String else {
                    return ToolResult(
                        toolCallID: id,
                        content: ToolHelpers
                            .output(errors: ["Missing 'reminder_id' for complete."]),
                        isError: true
                    )
                }
                try await service.completeReminder(id: reminderID)
                return ToolResult(
                    toolCallID: id,
                    content: ToolHelpers.output(result: [
                        "status": "completed",
                        "reminder_id": reminderID,
                    ]),
                    isError: false
                )

            case "delete":
                guard let reminderID = args["reminder_id"] as? String else {
                    return ToolResult(
                        toolCallID: id,
                        content: ToolHelpers.output(errors: ["Missing 'reminder_id' for delete."]),
                        isError: true
                    )
                }
                try await service.deleteReminder(id: reminderID)
                return ToolResult(
                    toolCallID: id,
                    content: ToolHelpers.output(result: [
                        "status": "deleted",
                        "reminder_id": reminderID,
                    ]),
                    isError: false
                )

            default:
                return ToolResult(
                    toolCallID: id,
                    content: ToolHelpers
                        .output(
                            errors: [
                                "Unknown action '\(action)'. Use 'create', 'update', 'complete', or 'delete'.",
                            ]
                        ),
                    isError: true
                )
            }
        } catch {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: [error.localizedDescription]),
                isError: true
            )
        }
    }
}
