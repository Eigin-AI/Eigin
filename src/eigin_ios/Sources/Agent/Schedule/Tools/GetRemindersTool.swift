import Foundation

struct GetRemindersTool: Tool {
    static let capability = ToolCapability(
        kind: .builtIn, key: "get_reminders",
        displayName: Localized.Tools.Schedule.getReminders,
        defaultPermissionLevel: .always, category: .system
    )

    let name = "get_reminders"
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
        .always
    }

    func definition() -> ToolDefinition {
        ToolDefinition(
            name: name,
            description: "Get reminders, optionally filtered by list, completion status, or a date range. A reminder is included if its due date OR creation date falls within the window: from 4 weeks before today through 4 weeks after today, by default (28 days in each direction). When an explicit date range is provided, the due date OR creation date must fall within that range. Reminders without a due date are included when their creation date falls within the window.",
            parameters: JSONSchema(
                type: "object",
                properties: [
                    "list_id": .init(
                        type: "string",
                        description: "Filter to a specific reminder list ID. Omit to search all lists."
                    ),
                    "start_date": .init(
                        type: "string",
                        description: "Date range start, e.g. \"2026-03-22\". Reminders are included if their due date OR creation date falls on or after this date."
                    ),
                    "end_date": .init(
                        type: "string",
                        description: "Date range end, e.g. \"2026-03-29\". Reminders are included if their due date OR creation date falls on or before this date."
                    ),
                    "include_completed": .init(
                        type: "boolean",
                        description: "Whether to include completed reminders. Defaults to false. Still limited to the default 4-week lookback and 4-week lookahead when no date range is given."
                    ),
                ]
            )
        )
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

        let args = ToolHelpers.parseArguments(toolCall.function.arguments) ?? [:]

        let listID = args["list_id"] as? String
        let startDate = (args["start_date"] as? String).flatMap { LocalDateFormatter.parse($0) }
        let endDate = (args["end_date"] as? String).flatMap { LocalDateFormatter.parse(
            $0,
            endOfDayIfDateOnly: true
        ) }
        let includeCompleted = args["include_completed"] as? Bool ?? false

        do {
            let reminders = try await service.fetchReminders(
                listID: listID, from: startDate, to: endDate, includeCompleted: includeCompleted
            )
            let lists = service.availableReminderLists()

            let reminderDicts: [[String: Any]] = reminders.map { reminder in
                var dict: [String: Any] = [
                    "id": reminder.id,
                    "title": reminder.title,
                    "is_completed": reminder.isCompleted,
                    "list_name": reminder.listName,
                    "list_id": reminder.listID,
                    "priority": reminder.priority,
                ]
                if let dueDate = reminder.dueDate {
                    dict["due_date"] = LocalDateFormatter.string(from: dueDate)
                }
                if let notes = reminder.notes { dict["notes"] = notes }
                return dict
            }

            let listDicts: [[String: Any]] = lists.map { list in
                ["id": list.id, "name": list.name, "is_default": list.isDefault]
            }

            let result: [String: Any] = [
                "reminders": reminderDicts,
                "available_lists": listDicts,
            ]
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(result: result),
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
