import Factory
import SwiftData
import UserNotifications

/// Interactive review fixtures confined to the screenshot mode's in-memory store.
@MainActor enum ScreenshotWaitingInitiatives {
    static func seed(_ context: ModelContext, agent: Agent) {
        // The screenshot installer uses PreviewChatService; no provider receives these fixtures.
        Container.shared.aiConsentStore.register { ScreenshotInitiativeConsent() }
        let messages = [
            "Ready for your weekly review? Let’s look back at what went well and pick a focus for next week.",
            "Shall we plan dinner for tonight?",
            "Want to take a look at your week?",
            "Ready for a quick check-in?",
            "Shall we catch up on the news?",
        ]
        let now = Date.now
        for (index, message) in messages.enumerated() {
            let due = now.addingTimeInterval(-Double(index + 1) * 3600)
            let components = Calendar.current.dateComponents([.hour, .minute], from: due)
            let schedule = IntentSchedule(
                content: "Review invitation",
                frequency: .daily,
                hour: components.hour,
                minute: components.minute
            )
            let intent = Intent(agentID: agent.id, content: "Review routine", schedules: [schedule])
            context.insert(intent)
            context.insert(IntentInitiative(
                intentID: intent.id,
                scheduleID: schedule.id,
                instructions: "Start a friendly conversation about this routine.",
                notificationBody: message
            ))
        }
        let followUp = AgentInitiativeRequest(
            agentID: agent.id,
            message: "Here’s the checklist we agreed on for your appointment: bring your notes, your medication list, and the questions you wanted to ask. Which part would you like to go over?",
            title: "Your appointment",
            summary: "The user asked to receive their appointment checklist today."
        )
        followUp.dueAt = now.addingTimeInterval(-1800)
        context.insert(followUp)
        try! context.save()
        try! WaitingInitiativeStore.reconcile(context: context, now: now.addingTimeInterval(-86400))
        try! WaitingInitiativeStore.reconcile(context: context, now: now)
        let container = context.container
        Container.shared.initiativeService.register { @MainActor in
            InitiativeService(modelContainer: container, scheduler: InitiativeNotificationScheduler(
                notifications: ScreenshotInitiativeNotifications(),
                authorization: ScreenshotInitiativeAuthorization()
            ))
        }
        try! Container.shared.initiativeService().refreshWaiting()
    }
}

@MainActor private struct ScreenshotInitiativeNotifications: InitiativeNotificationAccess {
    func pending() async -> [UNNotificationRequest] {
        []
    }

    func add(_: UNNotificationRequest) async throws {}
    func removePending(_: [String]) {}
    func delivered() async -> [DeliveredInitiativeNotification] {
        []
    }

    func removeDelivered(_: [String]) {}
}

private struct ScreenshotInitiativeAuthorization: NotificationAuthorizationAccess {
    func authorizationStatus() async -> UNAuthorizationStatus {
        .denied
    }

    func requestAuthorization() async throws -> Bool {
        false
    }
}

private struct ScreenshotInitiativeConsent: AIConsentStore {
    func isAllowed(baseURL: String) -> Bool {
        true
    }

    func allow(baseURL: String) {}
}
