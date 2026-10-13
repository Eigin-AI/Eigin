import Factory
import Foundation

/// Reminder tools, built for a connected Apple Reminders integration.
enum ReminderToolKit: ToolKit {
    static let capabilities: [ToolCapability] = [
        GetRemindersTool.capability,
        ManageReminderTool.capability,
    ]

    @MainActor static func tools(context: ToolContext) -> [any Tool] {
        let reminderService = Container.shared.reminderService()

        return [
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
