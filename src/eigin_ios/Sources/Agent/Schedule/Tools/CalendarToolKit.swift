import Factory
import Foundation

/// Calendar tools, built for a connected Apple Calendar integration.
enum CalendarToolKit: ToolKit {
    static let capabilities: [ToolCapability] = [
        GetCalendarEventsTool.capability,
        CreateCalendarEventTool.capability,
        ManageCalendarEventTool.capability,
    ]

    @MainActor static func tools(context: ToolContext) -> [any Tool] {
        let calendarService = Container.shared.calendarService()

        return [
            GetCalendarEventsTool(
                calendarService: calendarService,
                canPromptUser: context.canPromptUser
            ),
            CreateCalendarEventTool(
                calendarService: calendarService,
                canPromptUser: context.canPromptUser
            ),
            ManageCalendarEventTool(
                calendarService: calendarService,
                canPromptUser: context.canPromptUser
            ),
        ]
    }
}
