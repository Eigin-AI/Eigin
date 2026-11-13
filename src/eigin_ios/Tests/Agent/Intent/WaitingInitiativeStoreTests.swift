@testable import Eigin
import Foundation
import SwiftData
import Testing

@Suite("Waiting initiative lifecycle")
@MainActor
struct WaitingInitiativeStoreTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    private let baseline = Date(timeIntervalSince1970: 1_767_225_600) // 2026-01-01 UTC

    @Test(arguments: [
        ("Invitation 1", "Invitation 1"),
        (
            "Review this week’s meals and plan next week’s groceries",
            "Review this week’s meals and plan next"
        ),
        ("Læs bl.a. om søvn", "Læs bl.a. om søvn"),
    ])
    func openingSeedsTitle(invitation: String, expected: String) throws {
        let f = try fixture(count: 1)
        let agreement = try #require(f.mainContext.fetch(FetchDescriptor<IntentInitiative>()).first)
        agreement.notificationBody = invitation
        try f.mainContext.save()
        try reconcile(f, at: baseline)
        try reconcile(f, at: baseline.addingTimeInterval(3600))
        let item = try #require(items(f).first)
        let id = try WaitingInitiativeStore.open(id: item.id, context: f.mainContext)
        let context = ModelContext(f)
        let chat = try #require(context.fetch(FetchDescriptor<Chat>()).first)
        #expect(chat.id == id)
        #expect(chat.title == expected)
        #expect(chat.titleOrigin == .seeded)

        chat.title = "My title"
        chat.titleOrigin = .edited
        try context.save()
        let reopenedContext = ModelContext(f)
        #expect(try WaitingInitiativeStore.open(id: item.id, context: reopenedContext) == id)
        let reopened = try #require(reopenedContext.fetch(FetchDescriptor<Chat>()).first)
        #expect(reopened.title == "My title")
        #expect(reopened.titleOrigin == .edited)
        #expect(try reopenedContext.fetchCount(FetchDescriptor<Chat>()) == 1)
    }

    @Test func upgradeBaselineDoesNotBackfillAndSurvivesNewContext() throws {
        let f = try fixture(count: 1)
        try reconcile(f, at: baseline.addingTimeInterval(86400))
        #expect(try items(f).isEmpty)
        try WaitingInitiativeStore.reconcile(
            context: ModelContext(f),
            now: baseline.addingTimeInterval(86401),
            calendar: calendar
        )
        #expect(try items(f).isEmpty)
        try reconcile(f, at: baseline.addingTimeInterval(86400 + 3600))
        #expect(try items(f).count == 1)
    }

    @Test func newestFiveAcrossSpacesNeverRefillAfterDismissOpenOrRelaunch() throws {
        let f = try fixture(count: 7)
        try reconcile(f, at: baseline)
        try reconcile(f, at: baseline.addingTimeInterval(8 * 3600))
        let waiting = try items(f)
        #expect(waiting.count == 5)
        #expect(waiting.map(\.body) == [
            "Invitation 7",
            "Invitation 6",
            "Invitation 5",
            "Invitation 4",
            "Invitation 3",
        ])
        let opened = try WaitingInitiativeStore.open(id: waiting[0].id, context: f.mainContext)
        #expect(try WaitingInitiativeStore
            .open(id: waiting[0].id, context: ModelContext(f)) == opened)
        try WaitingInitiativeStore.dismiss(id: waiting[1].id, context: f.mainContext)
        try WaitingInitiativeStore.reconcile(
            context: ModelContext(f),
            now: baseline.addingTimeInterval(9 * 3600),
            calendar: calendar
        )
        #expect(try items(f).count == 3)
        #expect(try f.mainContext.fetch(FetchDescriptor<IntentInitiative>()).allSatisfy(\.enabled))
        try reconcile(f, at: baseline.addingTimeInterval(86400 + 8 * 3600))
        #expect(try items(f).count == 5)
        #expect(try items(f).allSatisfy { $0.dueAt > baseline.addingTimeInterval(86400) })
    }

    @Test func latestPerInitiativeAndUpcomingExcluded() throws {
        let f = try fixture(count: 2)
        try reconcile(f, at: baseline)
        try reconcile(f, at: baseline.addingTimeInterval(3600))
        #expect(try items(f).map(\.body) == ["Invitation 1"])
        try reconcile(f, at: baseline.addingTimeInterval(30 * 86400 + 90 * 60))
        let waiting = try items(f)
        #expect(waiting.count == 2)
        #expect(Set(waiting.map(\.initiativeID)).count == 2)
        #expect(waiting[0].dueAt == baseline.addingTimeInterval(30 * 86400 + 3600))
    }

    @Test func revisionCancellationAndClockRollbackCannotReviveInvitations() throws {
        let f = try fixture(count: 1)
        try reconcile(f, at: baseline)
        try reconcile(f, at: baseline.addingTimeInterval(7200))
        let old = try #require(items(f).first)
        try WaitingInitiativeStore.dismiss(id: old.id, context: f.mainContext)
        try reconcile(f, at: baseline)
        try reconcile(f, at: baseline.addingTimeInterval(7200))
        #expect(try items(f).isEmpty)
        let agreement = try #require(f.mainContext.fetch(FetchDescriptor<IntentInitiative>()).first)
        agreement.notificationBody = "Revised invitation"
        agreement.updatedAt = baseline.addingTimeInterval(7201)
        try reconcile(f, at: baseline.addingTimeInterval(7201))
        #expect(try items(f).isEmpty)
        try reconcile(f, at: baseline.addingTimeInterval(86400 + 7200))
        #expect(try items(f).first?.body == "Revised invitation")
        agreement.enabled = false
        try reconcile(f, at: baseline.addingTimeInterval(86400 + 7201))
        #expect(try items(f).isEmpty)
    }

    @Test func retentionIsPerAgentAndTieOrderingIsStable() throws {
        let f = try fixture(count: 7)
        let second = Agent(name: "Second", providerID: UUID(), model: "test")
        f.mainContext.insert(second)
        let intent = Intent(
            agentID: second.id,
            content: "Other agent",
            schedules: [IntentSchedule(content: "Other", frequency: .daily, hour: 1, minute: 0)]
        )
        f.mainContext.insert(intent)
        f.mainContext.insert(IntentInitiative(
            intentID: intent.id,
            scheduleID: intent.schedules[0].id,
            instructions: "Help",
            notificationBody: "Other"
        ))
        try reconcile(f, at: baseline)
        try reconcile(f, at: baseline.addingTimeInterval(8 * 3600))
        #expect(try items(f).count == 6)
        #expect(try items(f).count(where: { $0.agentID == second.id }) == 1)
        let ids = try items(f).map(\.id)
        try reconcile(f, at: baseline.addingTimeInterval(9 * 3600))
        #expect(try items(f).map(\.id) == ids)
    }

    @Test func calendarTransitionsRemainIdempotent() throws {
        let f = try fixture(count: 1)
        var c = calendar
        c.timeZone = try #require(TimeZone(identifier: "Europe/Copenhagen"))
        for day in ["2026-03-29T00:00:00Z", "2026-10-25T00:00:00Z"] {
            let start = try #require(ISO8601DateFormatter().date(from: day))
            try WaitingInitiativeStore.reconcile(context: f.mainContext, now: start, calendar: c)
            try WaitingInitiativeStore.reconcile(
                context: f.mainContext,
                now: start.addingTimeInterval(86400),
                calendar: c
            )
            let ids = try items(f).map(\.id)
            try WaitingInitiativeStore.reconcile(
                context: ModelContext(f),
                now: start.addingTimeInterval(86400),
                calendar: c
            )
            #expect(try items(f).map(\.id) == ids)
        }
    }

    @Test func notificationAndCardShareClaimAfterTimeZoneAndAgreementChanges() throws {
        let f = try fixture(count: 1)
        try reconcile(f, at: baseline)
        let due = baseline.addingTimeInterval(3600)
        try reconcile(f, at: due)
        let item = try #require(items(f).first)
        let cardChat = try WaitingInitiativeStore.open(id: item.id, context: f.mainContext)
        var traveled = calendar
        traveled.timeZone = try #require(TimeZone(identifier: "Asia/Tokyo"))
        let agreement = try #require(f.mainContext.fetch(FetchDescriptor<IntentInitiative>()).first)
        agreement.enabled = false
        try f.mainContext.save()
        let notificationChat = try InitiativeConversationService.open(
            registrationID: item.registrationID, deliveredAt: due.addingTimeInterval(10),
            context: ModelContext(f), now: due.addingTimeInterval(60), calendar: traveled
        )
        #expect(notificationChat == cardChat)
        #expect(try f.mainContext.fetchCount(FetchDescriptor<Chat>()) == 1)
    }

    @Test func notificationFirstOpensWaitingOccurrenceAndDismissedDeliveryCannotReturn() throws {
        let f = try fixture(count: 2)
        try reconcile(f, at: baseline)
        let now = baseline.addingTimeInterval(3 * 3600)
        try reconcile(f, at: now)
        let waiting = try items(f)
        let first = waiting[0]
        let chat = try InitiativeConversationService.open(
            registrationID: first.registrationID,
            deliveredAt: first.dueAt
                .addingTimeInterval(10),
            context: f.mainContext,
            now: now,
            calendar: calendar
        )
        #expect(try WaitingInitiativeStore.open(id: first.id, context: f.mainContext) == chat)
        let second = waiting[1]
        try WaitingInitiativeStore.dismiss(id: second.id, context: f.mainContext)
        #expect(throws: (any Error).self) {
            try InitiativeConversationService.open(
                registrationID: second.registrationID,
                deliveredAt: second.dueAt,
                context: f.mainContext,
                now: now,
                calendar: calendar
            )
        }
        #expect(try items(f).isEmpty)
    }

    @Test func unopenedLegacyDeliveryIsRejected() throws {
        let f = try fixture(count: 1)
        let deliveries = try InitiativeNotificationScheduler().compile(
            context: f.mainContext,
            otherRequestCount: 0
        )
        var delivery = try #require(deliveries.first)
        delivery.identityVersion = nil
        let registration = try InitiativeRegistration(id: "legacy", payload: delivery.encoded())
        f.mainContext.insert(registration)
        try f.mainContext.save()
        #expect(throws: (any Error).self) {
            try InitiativeConversationService.open(
                registrationID: registration.id,
                deliveredAt: baseline,
                context: f.mainContext,
                now: baseline,
                calendar: calendar
            )
        }
        #expect(try f.mainContext.fetchCount(FetchDescriptor<Chat>()) == 0)
    }

    @Test func repeatedDSTHourHasOneIdentityAndMissingHourMatchesForwardSchedule() throws {
        var c = calendar
        c.timeZone = try #require(TimeZone(identifier: "Europe/Copenhagen"))
        let schedule = IntentSchedule(content: "Daily", frequency: .daily, hour: 2, minute: 30)
        let parser = ISO8601DateFormatter()
        let first = try #require(parser.date(from: "2026-10-25T00:30:00Z"))
        let second = try #require(parser.date(from: "2026-10-25T01:30:00Z"))
        #expect(WaitingInitiativeStore.latest(schedule, at: first, calendar: c) == first)
        #expect(WaitingInitiativeStore.latest(schedule, at: second, calendar: c) == first)
        let spring = try #require(parser.date(from: "2026-03-29T01:00:00Z"))
        #expect(WaitingInitiativeStore.latest(schedule, at: spring, calendar: c) == spring)
    }

    private func fixture(count: Int) throws -> ModelContainer {
        let container = try ModelContainer(
            for: Schema(SchemaV15.models, version: SchemaV15.versionIdentifier),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let agent = Agent(name: "Agent", providerID: UUID(), model: "test")
        let space = Space(agentID: agent.id)
        context.insert(agent)
        context.insert(space)
        for index in 1 ... count {
            let schedule = IntentSchedule(
                content: "Daily",
                frequency: .daily,
                hour: index,
                minute: 0
            )
            let intent = Intent(agentID: agent.id, content: "Routine", schedules: [schedule])
            intent.spaceID = index.isMultiple(of: 2) ? space.id : nil
            context.insert(intent)
            context.insert(IntentInitiative(
                intentID: intent.id,
                scheduleID: schedule.id,
                instructions: "Help with this routine",
                notificationBody: "Invitation \(index)"
            ))
        }
        try context.save()
        return container
    }

    private func reconcile(_ container: ModelContainer, at now: Date) throws {
        try WaitingInitiativeStore.reconcile(
            context: container.mainContext,
            now: now,
            calendar: calendar
        )
    }

    private func items(_ container: ModelContainer) throws -> [WaitingInitiative] {
        try ModelContext(container).fetch(FetchDescriptor<WaitingInitiative>())
            .sorted(by: WaitingInitiativeStore.newestFirst)
    }
}
