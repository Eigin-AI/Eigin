import Foundation

struct CreateCalendarEventTool: Tool {
    static let capability = ToolCapability(
        kind: .builtIn, key: "create_calendar_event",
        displayName: Localized.Tools.Schedule.createEvent,
        defaultPermissionLevel: .ask, category: .calendar
    )

    let name = "create_calendar_event"
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
        .ask
    }

    func definition() -> ToolDefinition {
        if isSmallContext {
            return ToolDefinition(
                name: name,
                description: "Create a calendar event.",
                parameters: JSONSchema(
                    type: "object",
                    properties: [
                        "title": .init(type: "string", description: "Event title."),
                        "start_date": .init(type: "string", description: "Start date/time."),
                        "end_date": .init(type: "string", description: "End date/time."),
                    ],
                    required: ["title", "start_date", "end_date"]
                )
            )
        }
        return ToolDefinition(
            name: name,
            description: "Create a new calendar event.",
            parameters: JSONSchema(
                type: "object",
                properties: [
                    "title": .init(
                        type: "string",
                        description: "Event title."
                    ),
                    "start_date": .init(
                        type: "string",
                        description: "Start date/time (e.g. \"2026-03-25 14:00\")."
                    ),
                    "end_date": .init(
                        type: "string",
                        description: "End date/time (e.g. \"2026-03-25 15:00\")."
                    ),
                    "calendar_id": .init(
                        type: "string",
                        description: "Target calendar ID. Omit for user's default calendar."
                    ),
                    "location": .init(
                        type: "string",
                        description: "Event location."
                    ),
                    "notes": .init(
                        type: "string",
                        description: "Event notes."
                    ),
                    "is_all_day": .init(
                        type: "boolean",
                        description: "Whether this is an all-day event. Defaults to false."
                    ),
                ],
                required: ["title", "start_date", "end_date"]
            )
        )
    }

    func disclosure(for toolCall: ToolCall) -> ToolDisclosure? {
        guard let title = ToolHelpers.stringArgument(toolCall, "title") else { return nil }

        var summary = title
        if let startString = ToolHelpers.stringArgument(toolCall, "start_date"),
           let start = LocalDateFormatter.parse(startString)
        {
            var endText: String?
            if let endString = ToolHelpers.stringArgument(toolCall, "end_date"),
               let end = LocalDateFormatter.parse(endString)
            {
                // Same-day ranges drop the repeated date: "Fri, Sep 11, 12:00 to 13:30".
                endText = Calendar.current.isDate(end, inSameDayAs: start)
                    ? EventTimestamp.time(for: end)
                    : EventTimestamp.string(for: end)
            }
            let when: String = if let endText {
                Localized.Permission.Disclosure.rangeFormat(
                    EventTimestamp.string(for: start),
                    endText
                )
            } else {
                EventTimestamp.string(for: start)
            }
            summary = "\(title) (\(when))"
        }
        if let location = ToolHelpers.stringArgument(toolCall, "location") {
            summary += ", \(location)"
        }

        return ToolDisclosure(
            actionPhrase: Localized.Permission.Disclosure.addCalendarEvent,
            detail: .inline(summary)
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

        guard let title = args["title"] as? String else {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: ["Missing 'title'."]),
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
              let endDate = LocalDateFormatter.parse(endString)
        else {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: ["Missing or invalid 'end_date'."]),
                isError: true
            )
        }

        let newEvent = NewCalendarEvent(
            title: title,
            startDate: startDate,
            endDate: endDate,
            calendarID: args["calendar_id"] as? String,
            location: args["location"] as? String,
            notes: args["notes"] as? String,
            isAllDay: args["is_all_day"] as? Bool ?? false
        )

        do {
            let eventID = try await service.createEvent(newEvent)
            let result: [String: Any] = ["event_id": eventID, "title": title]
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
