@testable import Eigin
import Foundation
import Testing

@Suite("WithTimeout")
struct WithTimeoutTests {
    @Test("returns the result when the operation wins the race")
    func returnsResult() async {
        let result = await withTimeout(.seconds(2)) {
            try? await Task.sleep(for: .milliseconds(10))
            return "done"
        }
        #expect(result == "done")
    }

    @Test("returns nil when the timeout wins the race")
    func returnsNilOnTimeout() async {
        let start = ContinuousClock.now
        let result = await withTimeout(.milliseconds(50)) {
            try? await Task.sleep(for: .seconds(5))
            return "late"
        }
        #expect(result == nil)
        #expect(ContinuousClock.now - start < .seconds(4))
    }

    @Test("cancels the operation when the timeout wins")
    func cancelsOperation() async {
        let box = CancellationBox()
        let result = await withTimeout(.milliseconds(50)) {
            for _ in 0 ..< 500 {
                if Task.isCancelled {
                    box.value = true
                    break
                }
                try? await Task.sleep(for: .milliseconds(10))
            }
            return "loop-finished"
        }
        // Give the cancelled task a moment to observe cancellation.
        try? await Task.sleep(for: .milliseconds(100))
        #expect(result == nil)
        #expect(box.value)
    }

    /// Sendable box so the test closure can report what it saw.
    private final class CancellationBox: @unchecked Sendable {
        var value = false
    }
}
