import BackgroundTasks
@testable import Eigin
import SwiftData
import Testing

@Suite("BackgroundPromptScheduler", .serialized)
@MainActor
struct BackgroundPromptSchedulerTests {
    let fake = FakeBackgroundTaskScheduler()

    init() {
        BackgroundPromptScheduler.scheduler = fake
    }

    @Test("reschedule cancels existing and submits new request")
    func rescheduleCancelsAndSubmits() throws {
        try BackgroundPromptScheduler.reschedule(for: .proactive, in: context())

        #expect(fake.cancelledIdentifiers == [BackgroundPromptScheduler.taskIdentifier])
        #expect(fake.submittedRequests.count == 1)
        #expect(fake.submittedRequests.first?.identifier == BackgroundPromptScheduler
            .taskIdentifier)
    }

    @Test("reschedule for reactive cancels only, no submit")
    func rescheduleReactiveCancelsOnly() {
        BackgroundPromptScheduler.reschedule(for: .reactive, in: nil)

        #expect(fake.cancelledIdentifiers == [BackgroundPromptScheduler.taskIdentifier])
        #expect(fake.submittedRequests.isEmpty)
    }

    @Test("scheduleIfNeeded with no pending task submits")
    func scheduleIfNeededSubmitsWhenNoPending() async throws {
        try await BackgroundPromptScheduler.scheduleIfNeeded(for: .balanced, in: context())

        #expect(fake.submittedRequests.count == 1)
        #expect(fake.submittedRequests.first?.identifier == BackgroundPromptScheduler
            .taskIdentifier)
    }

    @Test("scheduleIfNeeded with existing pending task is a no-op")
    func scheduleIfNeededNoOpWhenPending() async throws {
        let existing = BGProcessingTaskRequest(identifier: BackgroundPromptScheduler.taskIdentifier)
        fake.addPendingRequest(existing)

        try await BackgroundPromptScheduler.scheduleIfNeeded(for: .proactive, in: context())

        #expect(fake.submittedRequests.isEmpty)
        #expect(fake.cancelledIdentifiers.isEmpty)
    }

    @Test("scheduleIfNeeded cancels for reactive")
    func scheduleIfNeededReactiveCancels() async throws {
        try await BackgroundPromptScheduler.scheduleIfNeeded(for: .reactive, in: context())

        #expect(fake.submittedRequests.isEmpty)
        #expect(fake.cancelledIdentifiers == [BackgroundPromptScheduler.taskIdentifier])
    }

    @Test func switchingToLocalCancelsPendingWorkAndReturningToCloudResumes() async throws {
        let context = try context()
        let agent = try #require(try context.fetch(Agent.primaryDescriptor).primary)
        let remoteID = agent.providerID
        let local = Provider(name: "On Device", baseURL: "local://")
        context.insert(local)
        agent.providerID = local.id
        BackgroundPromptScheduler.reschedule(for: .proactive, in: context)
        #expect(fake.submittedRequests.isEmpty)
        #expect(fake.cancelledIdentifiers.count == 1)
        await BackgroundPromptScheduler.scheduleIfNeeded(for: .proactive, in: context)
        #expect(fake.submittedRequests.isEmpty)
        #expect(fake.cancelledIdentifiers.count == 2)
        agent.providerID = remoteID
        await BackgroundPromptScheduler.scheduleIfNeeded(for: .proactive, in: context)
        #expect(fake.submittedRequests.count == 1)
    }

    private func context() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(SchemaV16.models, version: SchemaV16.versionIdentifier),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let provider = Provider(name: "Cloud", baseURL: "https://cloud.test")
        let agent = Agent(name: "Wren", providerID: provider.id, model: "test")
        let context = ModelContext(container)
        context.insert(provider)
        context.insert(agent)
        try context.save()
        return context
    }
}
