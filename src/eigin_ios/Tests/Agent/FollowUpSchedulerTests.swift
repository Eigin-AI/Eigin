@testable import Eigin
import Foundation
import SwiftData
import Testing
import UserNotifications

@Suite("FollowUpScheduler")
struct FollowUpSchedulerTests {
    @MainActor private func container() throws -> ModelContainer {
        try ModelContainer(
            for: AgentInitiativeRequest.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    @Test("Accepted notifications retain a briefing and its routing identifier")
    @MainActor func persistsAndSchedules() async throws {
        let container = try container()
        let center = FakeLocalNotificationCenter()
        let scheduler = DefaultFollowUpScheduler(container: container, notificationCenter: center)
        let agentID = UUID()
        let date = Date().addingTimeInterval(3600)
        let id = try await scheduler.schedule(
            title: "Hello",
            body: "Prepared message",
            message: "Prepared message",
            summary: "Briefing",
            deliverAt: date,
            agentID: agentID,
            agentName: nil,
            agentEmoji: nil
        )
        let records = try container.mainContext.fetch(FetchDescriptor<AgentInitiativeRequest>())
        let record = try #require(records.first)
        #expect(records.count == 1)
        #expect(record.id == id)
        #expect(record.summary == "Briefing")
        #expect(record.message == "Prepared message")
        let requests = await center.requests
        let request = try #require(requests.first)
        #expect(request.content.userInfo["initiativeRequestID"] as? String == id.uuidString)
        #expect(request.content.body == "Prepared message")
        let trigger = try #require(request.trigger as? UNCalendarNotificationTrigger)
        #expect(!trigger.repeats)
        #expect(try abs(#require(trigger.nextTriggerDate()).timeIntervalSince(date)) < 1)
    }

    @Test("Rejected notifications remove their persisted briefing")
    @MainActor func schedulingFailureCleansUp() async throws {
        let container = try container()
        let scheduler = DefaultFollowUpScheduler(
            container: container,
            notificationCenter: FakeLocalNotificationCenter(shouldFail: true)
        )
        do {
            _ = try await scheduler.schedule(
                title: "Hello",
                body: "Message",
                message: "Message",
                summary: nil,
                deliverAt: Date().addingTimeInterval(3600),
                agentID: UUID(),
                agentName: nil,
                agentEmoji: nil
            )
            Issue.record("Expected scheduling to fail")
        } catch {}
        #expect(try container.mainContext
            .fetchCount(FetchDescriptor<AgentInitiativeRequest>()) == 0)
    }

    @Test("Persistence failure never schedules a notification")
    @MainActor func persistenceFailure() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("notifications.store")
        do {
            let writable = try ModelContainer(
                for: AgentInitiativeRequest.self,
                configurations: ModelConfiguration(url: url)
            )
            try writable.mainContext.save()
        }
        let container = try ModelContainer(
            for: AgentInitiativeRequest.self,
            configurations: ModelConfiguration(url: url, allowsSave: false)
        )
        let center = FakeLocalNotificationCenter()
        let scheduler = DefaultFollowUpScheduler(container: container, notificationCenter: center)
        do {
            _ = try await scheduler.schedule(
                title: "Title",
                body: "Message",
                message: "Message",
                summary: nil,
                deliverAt: Date().addingTimeInterval(3600),
                agentID: UUID(),
                agentName: nil,
                agentEmoji: nil
            )
            Issue.record("Expected persistence to fail")
        } catch {}
        #expect(await center.requests.isEmpty)
    }

    @Test("A deadline elapsed during preparation fails and removes the briefing")
    @MainActor func elapsedDuringPreparation() async throws {
        let container = try container()
        let center = FakeLocalNotificationCenter()
        let deadline = Date().addingTimeInterval(60)
        var instant = deadline.addingTimeInterval(-60)
        let preparer = FakeCommunicationNotificationPreparer(onPrepare: {
            instant = deadline.addingTimeInterval(1)
        })
        let scheduler = DefaultFollowUpScheduler(
            now: { instant },
            container: container,
            contentPreparer: preparer,
            notificationCenter: center
        )
        do {
            _ = try await scheduler.schedule(
                title: "Title",
                body: "Message",
                message: "Message",
                summary: "Briefing",
                deliverAt: deadline,
                agentID: UUID(),
                agentName: "Agent",
                agentEmoji: nil
            )
            Issue.record("Expected the elapsed deadline to fail")
        } catch {
            #expect(error.localizedDescription.contains("Choose a new future time"))
        }
        #expect(center.requests.isEmpty)
        #expect(try container.mainContext
            .fetchCount(FetchDescriptor<AgentInitiativeRequest>()) == 0)
    }

    @Test("An omitted delivery time explicitly schedules immediate delivery")
    @MainActor func immediateDelivery() async throws {
        let container = try container()
        let center = FakeLocalNotificationCenter()
        let scheduler = DefaultFollowUpScheduler(container: container, notificationCenter: center)
        _ = try await scheduler.schedule(
            title: "Title",
            body: "Message",
            message: "Message",
            summary: nil,
            deliverAt: nil,
            agentID: UUID(),
            agentName: nil,
            agentEmoji: nil
        )
        let request = try #require(center.requests.first)
        #expect(request.trigger == nil)
    }
}
