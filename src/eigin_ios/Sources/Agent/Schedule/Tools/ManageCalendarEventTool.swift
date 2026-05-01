import Foundation

struct ManageCalendarEventTool: Tool {
    static let capability = ToolCapability(
        kind: .builtIn, key: "manage_calendar_event",
        displayName: Localized.Tools.Schedule.manageEvent,
        defaultPermissionLevel: .ask, category: .system
    )

    let name = "manage_calendar_event"
    var isSmallContext: Bool = false
    let calendarService: (any CalendarService)?
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
                description: "Update or delete a calendar event.",
                parameters: JSONSchema(
                    type: "object",
                    properties: [
                        "action": .init(
                            type: "string",
                            description: "Action.",
                            enum: ["update", "delete"]
                        ),
                        "event_id": .init(type: "string", description: "Event ID."),
                    ],
                    required: ["action", "event_id"]
                )
            )
        }
        return ToolDefinition(
            name: name,
            description: "Update or delete an existing calendar event.",
            parameters: JSONSchema(
                type: "object",
                properties: [
                    "action": .init(
                        type: "string",
                        description: "Action to perform.",
                        enum: ["update", "delete"]
                    ),
                    "event_id": .init(
                        type: "string",
                        description: "The event ID (from get_calendar_events)."
                    ),
                    "title": .init(
                        type: "string",
                        description: "New title (update only)."
                    ),
                    "start_date": .init(
                        type: "string",
                        description: "New start date/time (update only)."
                    ),
                    "end_date": .init(
                        type: "string",
                        description: "New end date/time (update only)."
                    ),
                    "location": .init(
                        type: "string",
                        description: "New location (update only)."
                    ),
                    "notes": .init(
                        type: "string",
                        description: "New notes (update only)."
                    ),
                ],
                required: ["action", "event_id"]
            )
        )
    }

    @MainActor func execute(_ toolCall: ToolCall, agent: Agent) async -> ToolResult {
        let id = toolCall.id

        guard let service = calendarService else {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: ["Calendar service unavailable."]),
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
        guard let eventID = args["event_id"] as? String else {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: ["Missing 'event_id'."]),
                isError: true
            )
        }

        do {
            switch action {
            case "update":
                let changes = CalendarEventChanges(
                    title: args["title"] as? String,
                    startDate: (args["start_date"] as? String)
                        .flatMap { LocalDateFormatter.parse($0) },
                    endDate: (args["end_date"] as? String).flatMap { LocalDateFormatter.parse($0) },
                    location: args["location"] as? String,
                    notes: args["notes"] as? String
                )
                try await service.updateEvent(id: eventID, changes: changes)
                return ToolResult(
                    toolCallID: id,
                    content: ToolHelpers.output(result: ["status": "updated", "event_id": eventID]),
                    isError: false
                )

            case "delete":
                try await service.deleteEvent(id: eventID)
                return ToolResult(
                    toolCallID: id,
                    content: ToolHelpers.output(result: ["status": "deleted", "event_id": eventID]),
                    isError: false
                )

            default:
                return ToolResult(
                    toolCallID: id,
                    content: ToolHelpers
                        .output(errors: ["Unknown action '\(action)'. Use 'update' or 'delete'."]),
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
