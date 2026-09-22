@testable import Eigin
import Testing

@Suite("BackgroundTaskGuard", .serialized)
@MainActor
struct BackgroundTaskGuardTests {
    @Test("the watchdog fires onExpiring once the budget runs low")
    func watchdogFiresOnLowBudget() async throws {
        let fired = SharedFlag()
        let guard_ = BackgroundTaskGuard(
            onExpiring: { fired.bump() },
            remainingTime: { 2 }
        )

        guard_.begin()
        defer { guard_.end() }

        try await waitFor { fired.count == 1 }

        #expect(fired.count == 1)
    }

    @Test("onExpiring fires exactly once even when expiry is re-driven")
    func expiryFiresOnlyOnce() async throws {
        let fired = SharedFlag()
        let guard_ = BackgroundTaskGuard(
            onExpiring: { fired.bump() },
            remainingTime: { 2 }
        )

        // An early end cancels the watchdog before its first poll; a renewed
        // budget gets a fresh monitor and still expires only once.
        guard_.begin()
        guard_.end()
        guard_.begin()
        defer { guard_.end() }

        try await waitFor { fired.count == 1 }

        #expect(fired.count == 1)
    }

    @Test("a healthy budget does not expire")
    func healthyBudgetStaysQuiet() async throws {
        let fired = SharedFlag()
        let guard_ = BackgroundTaskGuard(
            onExpiring: { fired.bump() },
            remainingTime: { 60 }
        )

        guard_.begin()
        defer { guard_.end() }

        try await Task.sleep(for: .seconds(2))

        #expect(fired.count == 0)
    }
}

@MainActor
private final class SharedFlag {
    private(set) var count = 0
    func bump() {
        count += 1
    }
}

@MainActor
private func waitFor(_ condition: () -> Bool, timeout: TimeInterval = 5) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
        if Date() > deadline {
            Issue.record("Timed out waiting for condition")
            return
        }
        try await Task.sleep(for: .milliseconds(50))
    }
}
