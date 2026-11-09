@testable import Eigin
import Foundation
import SwiftData
import Testing
import UserNotifications

@Suite("Initiative communication notifications")
@MainActor
struct InitiativeNotificationPresentationTests {
    @Test(arguments: [false, true])
    func communicationPresentationPreservesRecurrenceAndRouting(weekly: Bool) async throws {
        let container = try ModelContainer(
            for: Schema(SchemaV14.models, version: SchemaV14.versionIdentifier),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let agent = Agent(name: "News agent", providerID: UUID(), model: "test")
        agent.emoji = "📰"
        let schedule = IntentSchedule(
            content: "News",
            frequency: weekly ? .weekly : .daily,
            weekdays: weekly ? [2] : nil,
            hour: 10,
            minute: 57
        )
        let intent = Intent(agentID: agent.id, content: "News", schedules: [schedule])
        context.insert(agent)
        context.insert(intent)
        try context.save()
        let notifications = FakeInitiativeNotifications()
        let preparer = RecordingCommunicationNotificationPreparer()
        let scheduler = InitiativeNotificationScheduler(
            notifications: notifications,
            authorization: FakeNotificationAuthorization(status: .authorized),
            contentPreparer: preparer
        )
        let service = InitiativeService(modelContainer: container, scheduler: scheduler)
        _ = try await service.apply(
            [InitiativeChange(
                intentID: intent.id,
                scheduleID: schedule.id,
                instructions: "Get current news",
                body: "Time for your news"
            )],
            agentID: agent.id,
            spaceID: nil,
            canPromptUser: true
        )
        let request = try #require(notifications.requests.first)
        let call = try #require(preparer.calls.first)
        #expect(call.agentID == agent.id)
        #expect(call.agentName == agent.name)
        #expect(call.agentEmoji == agent.emoji)
        #expect(call.conversationID == request.identifier)
        #expect(request.content.categoryIdentifier == CommunicationNotificationContent
            .categoryIdentifier)
        #expect(request.content.title == agent.name)
        #expect(request.content.subtitle == "Prepared communication")
        #expect(request.content.body == "Time for your news")
        #expect(request.content.sound != nil)
        #expect(request.content.userInfo["scheduledInitiativeID"] as? String == request.identifier)
        let trigger = try #require(request.trigger as? UNCalendarNotificationTrigger)
        #expect(trigger.repeats)
        #expect(trigger.dateComponents.hour == 10)
        #expect(trigger.dateComponents.minute == 57)
        #expect(trigger.dateComponents.weekday == (weekly ? 2 : nil))
        #expect(trigger.dateComponents.timeZone == Calendar.current.timeZone)
        let originalPayload = try #require(context.fetch(FetchDescriptor<InitiativeRegistration>())
            .first?.payload)
        try await scheduler.reconcile(context: context)
        #expect(preparer.calls.count == 1)

        // Reconcile upgrades an already installed plain request under the same identifier.
        let plain = try #require(request.content.mutableCopy() as? UNMutableNotificationContent)
        plain.categoryIdentifier = ""
        plain.subtitle = ""
        notifications.requests = [UNNotificationRequest(
            identifier: request.identifier,
            content: plain,
            trigger: request.trigger
        )]
        try await scheduler.reconcile(context: context)
        #expect(preparer.calls.count == 2)
        #expect(notifications.requests.count == 1)
        let upgraded = try #require(notifications.requests.first)
        #expect(upgraded.identifier == request.identifier)
        #expect(upgraded.content.categoryIdentifier == CommunicationNotificationContent
            .categoryIdentifier)
        #expect(upgraded.content.subtitle == "Prepared communication")
        #expect(upgraded.content.userInfo["scheduledInitiativeID"] as? String == request.identifier)
        #expect((upgraded.trigger as? UNCalendarNotificationTrigger)?.dateComponents == trigger
            .dateComponents)
        #expect(try context.fetch(FetchDescriptor<InitiativeRegistration>()).first?
            .payload == originalPayload)
        for cursor in try context.fetch(FetchDescriptor<InitiativeCursor>()) {
            cursor.evaluatedThrough = Date.now.addingTimeInterval(-8 * 86400)
        }
        try context.save()
        let chatID = try InitiativeConversationService.open(
            registrationID: upgraded.identifier,
            deliveredAt: .now,
            context: context
        )
        #expect(try context.fetch(FetchDescriptor<Chat>()).first { $0.id == chatID }?
            .agentID == agent.id)
    }
}
