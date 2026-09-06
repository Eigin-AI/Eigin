import SwiftUI

/// `asks-first` — the assistant is about to create a calendar event and shows
/// its confirmation prompt, not yet accepted. The sheet is the real production
/// permission prompt over the canvas feed; the visible conversation is the
/// final exchange only.
enum ScreenshotAsksFirstScene {
    static let chatTitle = "Lunch on Friday"

    static var items: [ChatItem] {
        [
            .message(
                id: "asks-user",
                role: "user",
                content: "Put lunch with Martin in my calendar on Friday at noon. The usual place."
            ),
            .message(
                id: "asks-reply",
                role: "assistant",
                content: "You're free at noon, so I'll book Café Fjord from 12:00 to 1:30."
            ),
        ]
    }

    /// The call being approved, as the assistant composed it before asking.
    static var permissionRequest: PermissionRequest {
        let start = ScreenshotFixtures.nextWeekday(6, at: 12)
        let end = start.addingTimeInterval(5400)
        let call = ScreenshotFixtures.toolCall(
            "screenshot-permission",
            name: "create_calendar_event",
            arguments: """
            {"title": "Lunch with Martin",
             "start_date": "\(LocalDateFormatter.string(from: start))",
             "end_date": "\(LocalDateFormatter.string(from: end))",
             "location": "Café Fjord, Islands Brygge"}
            """
        )
        let tool = CreateCalendarEventTool(calendarService: nil, canPromptUser: true)
        return PermissionRequest(
            id: call.id,
            toolName: call.function.name,
            toolDisplayName: ToolRegistry.displayName(for: call.function.name),
            disclosure: tool.disclosure(for: call)
        )
    }
}
