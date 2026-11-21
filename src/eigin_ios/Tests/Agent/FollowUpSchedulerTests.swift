@testable import Eigin
import Foundation
import SwiftData
import Testing
import UserNotifications

@Suite("FollowUpScheduler")
struct FollowUpSchedulerTests {
    @MainActor private func fixture() throws -> (ModelContainer, Agent, Space) {
        let container = try ModelContainer(
            for: Schema(SchemaV15.models, version: SchemaV15.versionIdentifier),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let agent = Agent(name: "Test", providerID: UUID(), model: "test")
        let space = Space(agentID: agent.id)
        container.mainContext.insert(agent)
        container.mainContext.insert(space)
        try container.mainContext.save()
        return (container, agent, space)
    }

    @Test("Background final delivery rechecks a reservation created after preflight")
    @MainActor func backgroundFinalCollision() async throws {
        let (container, agent, _) = try fixture()
        let date = Date().addingTimeInterval(3600)
        #expect(try NotificationSpacingValidator(container: container).validate(date: date).isEmpty)
        let existing = AgentInitiativeRequest(
            agentID: agent.id,
            message: "Reserved after preflight"
        )
        existing.dueAt = date
        container.mainContext.insert(existing)
        try container.mainContext.save()
        let delivery = await BackgroundPromptScheduler.sendNotification(
            container: container,
            title: "New",
            body: "New",
            agentID: agent.id,
            message: "New",
            deliverAt: date
        )
        #expect(delivery.label == "spacing_conflict")
        #expect(!delivery.succeeded)
        #expect(try ModelContext(container)
            .fetchCount(FetchDescriptor<AgentInitiativeRequest>()) == 1)
    }

    @Test("Another agent's reserved time rejects a follow-up before any write or authorization")
    @MainActor func collisionAcrossAgents() async throws {
        let (container, agent, space) = try fixture()
        let other = Agent(name: "Other", providerID: UUID(), model: "test")
        let date = Date().addingTimeInterval(3600)
        let request = AgentInitiativeRequest(agentID: other.id, message: "Existing")
        request.dueAt = date
        container.mainContext.insert(other)
        container.mainContext.insert(request)
        try container.mainContext.save()
        let center = FakeLocalNotificationCenter()
        let scheduler = DefaultFollowUpScheduler(
            container: container,
            notificationCenter: center,
            authorize: { _ in
                Issue.record("Collision must fail before authorization")
                return true
            }
        )
        await #expect(throws: NotificationSpacingConflict.self) {
            _ = try await scheduler.schedule(
                title: "New",
                body: "New",
                message: "New",
                summary: nil,
                deliverAt: date,
                agentID: agent.id,
                agentName: nil,
                agentEmoji: nil,
                spaceID: space.id
            )
        }
        #expect(try ModelContext(container)
            .fetchCount(FetchDescriptor<AgentInitiativeRequest>()) == 1)
        #expect(center.requests.isEmpty)
    }

    @Test(
        "Future saved requests warn despite denied permission; handled and past requests do not reserve time"
    )
    @MainActor func warningAndLifecycle() async throws {
        let (container, agent, _) = try fixture()
        let instant = Date.now
        let date = instant.addingTimeInterval(3600)
        let existing = AgentInitiativeRequest(agentID: agent.id, message: "Existing")
        existing.dueAt = date.addingTimeInterval(600)
        let handled = AgentInitiativeRequest(agentID: agent.id, message: "Handled")
        handled.dueAt = date
        handled.handledAt = instant
        let discarded = AgentInitiativeRequest(agentID: agent.id, message: "Discarded")
        discarded.dueAt = date
        discarded.disposition = "discarded"
        let past = AgentInitiativeRequest(agentID: agent.id, message: "Past")
        past.dueAt = instant.addingTimeInterval(-1)
        for request in [existing, handled, discarded, past] {
            container.mainContext.insert(request)
        }
        try container.mainContext.save()
        let scheduler = DefaultFollowUpScheduler(
            now: { instant },
            container: container,
            authorize: { _ in false }
        )
        let result = try await scheduler.schedule(
            title: "New",
            body: "New",
            message: "New",
            summary: nil,
            deliverAt: date,
            agentID: agent.id,
            agentName: nil,
            agentEmoji: nil
        )
        #expect(result.deliveryStatus == .permissionDenied)
        #expect(result.warnings.count == 1)
        #expect(result.warnings.first?.existingAt == existing.dueAt)
    }

    @Test("A saved reservation blocks a second call while authorization is suspended")
    @MainActor func concurrentReservation() async throws {
        let (container, agent, _) = try fixture()
        let date = Date().addingTimeInterval(3600)
        let scheduler = DefaultFollowUpScheduler(container: container, authorize: { _ in
            let second = DefaultFollowUpScheduler(container: container, authorize: { _ in false })
            await #expect(throws: NotificationSpacingConflict.self) {
                _ = try await second.schedule(
                    title: "Second",
                    body: "Second",
                    message: "Second",
                    summary: nil,
                    deliverAt: date,
                    agentID: agent.id,
                    agentName: nil,
                    agentEmoji: nil
                )
            }
            return false
        })
        _ = try await scheduler.schedule(
            title: "First",
            body: "First",
            message: "First",
            summary: nil,
            deliverAt: date,
            agentID: agent.id,
            agentName: nil,
            agentEmoji: nil
        )
        #expect(try ModelContext(container)
            .fetchCount(FetchDescriptor<AgentInitiativeRequest>()) == 1)
    }

    @Test("Accepted notifications retain due time, source space, briefing and stable routing")
    @MainActor func persistsAndSchedules() async throws {
        let (container, agent, space) = try fixture()
        let center = FakeLocalNotificationCenter()
        var refreshed = false
        let scheduler = DefaultFollowUpScheduler(
            container: container,
            notificationCenter: center,
            authorize: { _ in true },
            onChange: { refreshed = true }
        )
        let date = Date().addingTimeInterval(3600)
        let result = try await scheduler.schedule(
            title: "Hello",
            body: "Prepared message",
            message: "Prepared message",
            summary: "Briefing",
            deliverAt: date,
            agentID: agent.id,
            agentName: nil,
            agentEmoji: nil,
            spaceID: space.id
        )
        let record = try #require(container.mainContext
            .fetch(FetchDescriptor<AgentInitiativeRequest>()).first)
        #expect(record.id == result.requestID)
        #expect(record.summary == "Briefing")
        #expect(record.message == "Prepared message")
        #expect(record.dueAt == date)
        #expect(record.spaceID == space.id)
        #expect(refreshed)
        #expect(result.deliveryStatus == .scheduled)
        let request = try #require(center.requests.first)
        #expect(request.identifier == "follow-up-\(record.id.uuidString)")
        #expect(request.content.userInfo["initiativeRequestID"] as? String == record.id.uuidString)
        let trigger = try #require(request.trigger as? UNCalendarNotificationTrigger)
        #expect(!trigger.repeats)
        let deliveredAt = try #require(trigger.nextTriggerDate())
        #expect(deliveredAt >= date)
        #expect(deliveredAt.timeIntervalSince(date) < 1)
        #expect(trigger.dateComponents.timeZone?.secondsFromGMT() == 0)
    }

    @Test(
        "Optional delivery failures preserve the saved message",
        arguments: ["denied", "capacity", "failed"]
    )
    @MainActor func deliveryFailure(kind: String) async throws {
        let (container, agent, _) = try fixture()
        let center = FakeLocalNotificationCenter(shouldFail: kind == "failed")
        if kind == "capacity" {
            for index in 0 ..< 64 {
                try await center.add(UNNotificationRequest(
                    identifier: "other-\(index)",
                    content: UNMutableNotificationContent(),
                    trigger: nil
                ))
            }
        }
        let scheduler = DefaultFollowUpScheduler(
            container: container,
            notificationCenter: center,
            authorize: { _ in
                #expect(try! ModelContext(container)
                    .fetchCount(FetchDescriptor<AgentInitiativeRequest>()) == 1)
                return kind != "denied"
            }
        )
        let result = try await scheduler.schedule(
            title: "Hello",
            body: "Message",
            message: "Message",
            summary: nil,
            deliverAt: Date().addingTimeInterval(3600),
            agentID: agent.id,
            agentName: nil,
            agentEmoji: nil
        )
        #expect(result
            .deliveryStatus ==
            (kind == "denied" ? .permissionDenied : kind == "capacity" ? .capacityExceeded :
                .failed))
        #expect(try container.mainContext
            .fetchCount(FetchDescriptor<AgentInitiativeRequest>()) == 1)
        #expect(center.requests.count == (kind == "capacity" ? 64 : 0))
    }

    @Test("A deadline elapsed during preparation keeps the message due in app")
    @MainActor func elapsedDuringPreparation() async throws {
        let (container, agent, _) = try fixture()
        let center = FakeLocalNotificationCenter()
        let deadline = Date().addingTimeInterval(60)
        var instant = deadline.addingTimeInterval(-60)
        let scheduler = DefaultFollowUpScheduler(
            now: { instant },
            container: container,
            contentPreparer: FakeCommunicationNotificationPreparer(onPrepare: {
                instant = deadline.addingTimeInterval(1)
            }),
            notificationCenter: center,
            authorize: { _ in true }
        )
        let result = try await scheduler.schedule(
            title: "Title",
            body: "Message",
            message: "Message",
            summary: "Briefing",
            deliverAt: deadline,
            agentID: agent.id,
            agentName: "Agent",
            agentEmoji: nil
        )
        #expect(result.deliveryStatus == .failed)
        #expect(center.requests.isEmpty)
        try WaitingInitiativeStore.reconcile(context: container.mainContext, now: instant)
        #expect(try WaitingMessageStore.messages(context: container.mainContext, now: instant)
            .count == 1)
    }

    @Test("Immediate delivery persists its actual due time")
    @MainActor func immediateDelivery() async throws {
        let (container, agent, _) = try fixture()
        let center = FakeLocalNotificationCenter()
        let instant = Date.now
        let scheduler = DefaultFollowUpScheduler(
            now: { instant },
            container: container,
            notificationCenter: center,
            authorize: { _ in true }
        )
        let result = try await scheduler.schedule(
            title: "Title",
            body: "Message",
            message: "Message",
            summary: nil,
            deliverAt: nil,
            agentID: agent.id,
            agentName: nil,
            agentEmoji: nil
        )
        #expect(result.dueAt == instant)
        #expect(try #require(center.requests.first).trigger == nil)
    }

    @Test("Persistence failure never requests authorization or schedules delivery")
    @MainActor func persistenceFailure() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("follow-ups.store")
        let schema = Schema(SchemaV15.models, version: SchemaV15.versionIdentifier)
        let agentID: UUID
        do {
            let writable = try ModelContainer(
                for: schema,
                configurations: ModelConfiguration(url: url)
            )
            let agent = Agent(name: "Test", providerID: UUID(), model: "test")
            agentID = agent.id
            writable.mainContext.insert(agent)
            try writable.mainContext.save()
        }
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(url: url, allowsSave: false)
        )
        let center = FakeLocalNotificationCenter()
        let scheduler = DefaultFollowUpScheduler(
            container: container,
            notificationCenter: center,
            authorize: { _ in
                Issue.record("Unsaved follow-up must not request authorization"); return true
            }
        )
        await #expect(throws: (any Error).self) {
            _ = try await scheduler.schedule(
                title: "Title",
                body: "Message",
                message: "Message",
                summary: nil,
                deliverAt: Date().addingTimeInterval(3600),
                agentID: agentID,
                agentName: nil,
                agentEmoji: nil
            )
        }
        #expect(center.requests.isEmpty)
    }
}
