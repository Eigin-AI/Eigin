import FixtureBindings
import XCTest

final class InferenceDeadlineTests: ContractTestCase {
    func testCancelWakesRegisteredDeadlineWait() async {
        await check {
            let attempts = InferenceAttempts(local: false, routed: true, maxBufferedBytes: 1, startingModel: "A")
            _ = attempts.step(observation: .start(hedgeDelayMs: nil, ceilingMs: 5000))
            let waiter = Task { await attempts.waitForDeadline() }
            let limit = ContinuousClock.now + .seconds(1)
            while !attempts.bindingWaitRegistered(), ContinuousClock.now < limit {
                await Task.yield()
            }
            XCTAssertTrue(attempts.bindingWaitRegistered())
            let cancelled = ContinuousClock.now
            _ = attempts.step(observation: .cancel)
            let due = await waiter.value
            XCTAssertFalse(due)
            XCTAssertLessThan(cancelled.duration(to: .now), .seconds(1))
        }
    }
}
