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
