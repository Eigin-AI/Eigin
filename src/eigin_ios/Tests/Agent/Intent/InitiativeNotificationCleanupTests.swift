@testable import Eigin
import Foundation
import SwiftData
import Testing
import UserNotifications

@Suite("Delivered initiative cleanup")
@MainActor
struct InitiativeNotificationCleanupTests {
    @Test(arguments: [false, true])
    func handlingAnInvitationRemovesOnlyItsDelivery(open: Bool) async throws {
        let f = try await fixture(count: 2)
        try f.service.refreshWaiting()
        let item = try #require(f.service.waiting.first)
        let stored = try #require(f.container.mainContext
            .fetch(FetchDescriptor<WaitingInitiative>())
            .first { item.id == "recurring:\($0.id)" })
        let registrationID = stored.registrationID
        let repeating = Set(f.center.requests.map(\.identifier))

        if open { _ = try f.service.openInvitation(id: item.id) }
        else { try f.service.dismissInvitation(id: item.id) }
        await f.service.cleanDeliveredNotifications()

        #expect(!f.center.deliveries.contains { $0.identifier == registrationID })
        #expect(f.center.deliveries.count == 2)
        #expect(f.center.deliveries.contains { $0.identifier == "unrelated" })
        #expect(Set(f.center.requests.map(\.identifier)) == repeating)
        #expect(try f.container.mainContext.fetch(FetchDescriptor<IntentInitiative>())
            .allSatisfy(\.enabled))
    }

    @Test func overflowRemovesDeliveriesWithoutCancellingFutureRequests() async throws {
        let f = try await fixture(count: 7)
        let repeating = Set(f.center.requests.map(\.identifier))
        await f.service.reconcile()

        let retained = try Set(f.container.mainContext.fetch(FetchDescriptor<WaitingInitiative>())
            .map(\.registrationID))
        #expect(retained.count == 5)
        #expect(Set(f.center.deliveries.map(\.identifier)) == retained.union(["unrelated"]))
        #expect(Set(f.center.requests.map(\.identifier)) == repeating)
        #expect(f.center.removedDeliveries.count == 2)
    }

    @Test func supersededDeliveriesDisappearWhileTheLatestInvitationRemains() async throws {
        let f = try await fixture(count: 1, deliveredDaysAgo: 1)
        let repeating = Set(f.center.requests.map(\.identifier))
        let oldDelivery = try #require(f.center.deliveries.first { $0.identifier != "unrelated" })
        await f.service.reconcile()

        let invitation = try #require(f.service.waiting.first)
        #expect(invitation.dueAt > oldDelivery.date)
        #expect(f.center.deliveries.map(\.identifier) == ["unrelated"])
        #expect(Set(f.center.requests.map(\.identifier)) == repeating)
    }

    @Test func travelReplacesPendingRequestsAndPreservesRetainedDelivery() async throws {
        let container = try ModelContainer(
            for: Schema(SchemaV14.models, version: SchemaV14.versionIdentifier),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let agent = Agent(name: "Agent", providerID: UUID(), model: "test")
        context.insert(agent)
        let schedule = IntentSchedule(content: "Daily", frequency: .daily, hour: 10, minute: 0)
        let intent = Intent(agentID: agent.id, content: "Routine", schedules: [schedule])
        context.insert(intent)
        context.insert(IntentInitiative(
            intentID: intent.id,
            scheduleID: schedule.id,
            instructions: "Help",
            notificationBody: "Invitation"
        ))
        try context.save()
        var origin = Calendar(identifier: .gregorian)
        origin.timeZone = try #require(TimeZone(identifier: "UTC"))
        var destination = origin
        destination.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let midnight = try #require(ISO8601DateFormatter().date(from: "2026-01-01T00:00:00Z"))
        let noon = midnight.addingTimeInterval(12 * 3600)
        let center = FakeInitiativeNotifications()
        let scheduler = InitiativeNotificationScheduler(
            notifications: center,
            authorization: FakeNotificationAuthorization(status: .authorized),
            contentPreparer: FakeCommunicationNotificationPreparer()
        )
        try WaitingInitiativeStore.reconcile(context: context, now: midnight, calendar: origin)
        try await scheduler.reconcile(context: context, calendar: origin)
        try WaitingInitiativeStore.reconcile(context: context, now: noon, calendar: origin)
        let waiting = try #require(context.fetch(FetchDescriptor<WaitingInitiative>()).first)
        let oldID = waiting.registrationID
        center.deliveries = [DeliveredInitiativeNotification(
            identifier: oldID,
            date: waiting.dueAt
        )]
        try WaitingInitiativeStore.reconcile(context: context, now: noon, calendar: destination)
        try await scheduler.reconcile(context: context, calendar: destination)
        let service = InitiativeService(modelContainer: container, scheduler: scheduler)
        await service.cleanDeliveredNotifications()
        #expect(!center.requests.contains { $0.identifier == oldID })
        #expect(center.requests.count == 1)
        #expect(center.deliveries.map(\.identifier) == [oldID])
        #expect(try context.fetchCount(FetchDescriptor<WaitingInitiative>()) == 1)
        try WaitingInitiativeStore.dismiss(id: waiting.id, context: context)
        await service.cleanDeliveredNotifications()
        #expect(center.deliveries.isEmpty)
        #expect(center.requests.count == 1)
    }

    @Test func cancellingAnAgreementRemovesItsDeliveryImmediately() async throws {
        let f = try await fixture(count: 2)
        let context = f.container.mainContext
        let item = try #require(context.fetch(FetchDescriptor<WaitingInitiative>()).first)
        try await f.service.cancel(
            id: item.initiativeID,
            agentID: item.agentID,
            spaceID: item.spaceID
        )
        #expect(!f.center.deliveries.contains { $0.identifier == item.registrationID })
        #expect(!f.center.requests.contains { $0.identifier == item.registrationID })
        #expect(f.center.deliveries.count == 2)
    }

    private func fixture(count: Int, deliveredDaysAgo: Int = 0) async throws -> Fixture {
        let container = try ModelContainer(
            for: Schema(SchemaV14.models, version: SchemaV14.versionIdentifier),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let agent = Agent(name: "Agent", providerID: UUID(), model: "test")
        context.insert(agent)
        let now = Date.now
        for index in 0 ..< count {
            let time = Calendar.current.dateComponents(
                [.hour, .minute],
                from: now.addingTimeInterval(-Double(index + 1) * 3600)
            )
            let schedule = IntentSchedule(
                content: "Daily",
                frequency: .daily,
                hour: time.hour,
                minute: time.minute
            )
            let intent = Intent(agentID: agent.id, content: "Routine", schedules: [schedule])
            context.insert(intent)
            context.insert(IntentInitiative(
                intentID: intent.id,
                scheduleID: schedule.id,
                instructions: "Help with the routine",
                notificationBody: "Invitation \(index)"
            ))
        }
        try context.save()
        try WaitingInitiativeStore.reconcile(
            context: context,
            now: now.addingTimeInterval(-3 * 86400)
        )
        let deliveryTime = now.addingTimeInterval(-Double(deliveredDaysAgo) * 86400)
        try WaitingInitiativeStore.reconcile(context: context, now: deliveryTime)
        let center = FakeInitiativeNotifications()
        let scheduler = InitiativeNotificationScheduler(
            notifications: center,
            authorization: FakeNotificationAuthorization(status: .authorized),
            contentPreparer: FakeCommunicationNotificationPreparer()
        )
        try await scheduler.reconcile(context: context)
        for delivery in try scheduler.compile(context: context, otherRequestCount: 0) {
            let member = try #require(delivery.members.first)
            let due = try #require(WaitingInitiativeStore.latest(
                member.schedule,
                at: deliveryTime,
                calendar: .current
            ))
            try center.deliveries.append(DeliveredInitiativeNotification(
                identifier: WaitingInitiativeStore.registrationID(for: delivery), date: due
            ))
        }
        center.deliveries.append(DeliveredInitiativeNotification(
            identifier: "unrelated",
            date: now
        ))
        center.removedDeliveries = []
        return Fixture(
            container: container,
            center: center,
            service: InitiativeService(modelContainer: container, scheduler: scheduler)
        )
    }

    private struct Fixture {
        let container: ModelContainer
        let center: FakeInitiativeNotifications
        let service: InitiativeService
    }
}
