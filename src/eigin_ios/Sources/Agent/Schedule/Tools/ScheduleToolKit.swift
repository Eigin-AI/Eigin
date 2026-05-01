import Factory
import Foundation

enum ScheduleToolKit: ToolKit {
    static let capabilities: [ToolCapability] = [
        GetCalendarEventsTool.capability,
        CreateCalendarEventTool.capability,
        ManageCalendarEventTool.capability,
        GetRemindersTool.capability,
        ManageReminderTool.capability,
    ]

    @MainActor static func tools(context: ToolContext) -> [any Tool] {
        let calendarService = Container.shared.calendarService()
        let reminderService = Container.shared.reminderService()

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
            GetRemindersTool(
                reminderService: reminderService,
                canPromptUser: context.canPromptUser
            ),
            ManageReminderTool(
                reminderService: reminderService,
                canPromptUser: context.canPromptUser
            ),
        ]
    }
}
