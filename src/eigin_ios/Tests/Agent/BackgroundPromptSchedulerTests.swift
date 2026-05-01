import BackgroundTasks
@testable import Eigin
import Testing

@Suite("BackgroundPromptScheduler", .serialized)
struct BackgroundPromptSchedulerTests {
    let fake = FakeBackgroundTaskScheduler()

    init() {
        BackgroundPromptScheduler.scheduler = fake
    }

    @Test("reschedule cancels existing and submits new request")
    func rescheduleCancelsAndSubmits() {
        BackgroundPromptScheduler.reschedule(for: .proactive)

        #expect(fake.cancelledIdentifiers == [BackgroundPromptScheduler.taskIdentifier])
        #expect(fake.submittedRequests.count == 1)
        #expect(fake.submittedRequests.first?.identifier == BackgroundPromptScheduler
            .taskIdentifier)
    }

    @Test("reschedule for reactive cancels only, no submit")
    func rescheduleReactiveCancelsOnly() {
        BackgroundPromptScheduler.reschedule(for: .reactive)

        #expect(fake.cancelledIdentifiers == [BackgroundPromptScheduler.taskIdentifier])
        #expect(fake.submittedRequests.isEmpty)
    }

    @Test("scheduleIfNeeded with no pending task submits")
    func scheduleIfNeededSubmitsWhenNoPending() async {
        await BackgroundPromptScheduler.scheduleIfNeeded(for: .balanced)

        #expect(fake.submittedRequests.count == 1)
        #expect(fake.submittedRequests.first?.identifier == BackgroundPromptScheduler
            .taskIdentifier)
    }

    @Test("scheduleIfNeeded with existing pending task is a no-op")
    func scheduleIfNeededNoOpWhenPending() async {
        let existing = BGProcessingTaskRequest(identifier: BackgroundPromptScheduler.taskIdentifier)
        fake.addPendingRequest(existing)

        await BackgroundPromptScheduler.scheduleIfNeeded(for: .proactive)

        #expect(fake.submittedRequests.isEmpty)
        #expect(fake.cancelledIdentifiers.isEmpty)
    }

    @Test("scheduleIfNeeded for reactive is a no-op")
    func scheduleIfNeededReactiveNoOp() async {
        await BackgroundPromptScheduler.scheduleIfNeeded(for: .reactive)

        #expect(fake.submittedRequests.isEmpty)
        #expect(fake.cancelledIdentifiers.isEmpty)
    }
}
