import Foundation

struct GetCalendarEventsTool: Tool {
    static let capability = ToolCapability(
        kind: .builtIn, key: "get_calendar_events",
        displayName: Localized.Tools.Schedule.getEvents,
        defaultPermissionLevel: .always, category: .calendar
    )

    let name = "get_calendar_events"
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
        .calendar
    }

    var defaultPermissionLevel: ToolPermissionLevel {
        .always
    }

    func definition() -> ToolDefinition {
        ToolDefinition(
            name: name,
            description: "Get calendar events for a date range. Returns events with their calendar names and IDs.",
            parameters: JSONSchema(
                type: "object",
                properties: [
                    "start_date": .init(
                        type: "string",
                        description: "Start of date range (e.g. \"2026-03-22\" or \"2026-03-22 09:00\")."
                    ),
                    "end_date": .init(
                        type: "string",
                        description: "End of date range (e.g. \"2026-03-23\")."
                    ),
                    "calendar_ids": .init(
                        type: "array",
                        description: "Optional list of calendar IDs to filter by. Omit to search all calendars.",
                        items: .init(type: "string")
                    ),
                ],
                required: ["start_date", "end_date"]
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

        guard let startString = args["start_date"] as? String,
              let startDate = LocalDateFormatter.parse(startString)
        else {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: ["Missing or invalid 'start_date'."]),
                isError: true
            )
        }
        guard let endString = args["end_date"] as? String,
              let endDate = LocalDateFormatter.parse(endString, endOfDayIfDateOnly: true)
        else {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: ["Missing or invalid 'end_date'."]),
                isError: true
            )
        }

        let calendarIDs = args["calendar_ids"] as? [String]

        do {
            let events = try await service.fetchEvents(
                from: startDate,
                to: endDate,
                calendarIDs: calendarIDs
            )
            let calendars = service.availableCalendars()

            let eventDicts: [[String: Any]] = events.map { event in
                var dict: [String: Any] = [
                    "id": event.id,
                    "title": event.title,
                    "start_date": LocalDateFormatter.string(from: event.startDate),
                    "end_date": LocalDateFormatter.string(from: event.endDate),
                    "is_all_day": event.isAllDay,
                    "calendar_name": event.calendarName,
                    "calendar_id": event.calendarID,
                ]
                if let location = event.location { dict["location"] = location }
                if let notes = event.notes { dict["notes"] = notes }
                return dict
            }

            let calendarDicts: [[String: Any]] = calendars.map { cal in
                ["id": cal.id, "name": cal.name, "is_default": cal.isDefault]
            }

            let result: [String: Any] = [
                "events": eventDicts,
                "available_calendars": calendarDicts,
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
