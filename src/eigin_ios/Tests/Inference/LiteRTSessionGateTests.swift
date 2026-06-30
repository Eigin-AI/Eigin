@testable import Eigin
import Testing

/// Verifies the session gate that serialises access to the single LiteRT engine
/// and gives foreground (interactive) work priority over background work.
@Suite("LiteRT session gate")
struct LiteRTSessionGateTests {
    private let noPreempt: @Sendable () -> Void = {}

    @Test("Acquires immediately when the session is free")
    func acquiresWhenFree() async {
        let gate = LiteRTSessionGate()
        let acquired = await gate.acquire(priority: .interactive, preempt: noPreempt)
        #expect(acquired)
        await gate.release()
    }

    @Test("Interactive acquirer preempts a running background holder")
    func interactivePreemptsBackgroundHolder() async {
        let gate = LiteRTSessionGate()
        let preempted = Preempted()

        // Background takes the session first.
        let bgAcquired = await gate.acquire(priority: .background) {
            Task { await preempted.fire() }
        }
        #expect(bgAcquired)

        // Interactive arrives; it can't acquire yet but must signal the holder
        // to yield via its preempt closure.
        let interactive = Task {
            await gate.acquire(priority: .interactive, preempt: noPreempt)
        }
        // Give the interactive acquire a moment to enqueue and fire preempt.
        try? await Task.sleep(for: .milliseconds(50))
        #expect(await preempted.didFire)

        // Holder yields → interactive proceeds.
        await gate.release()
        #expect(await interactive.value)
        await gate.release()
    }

    @Test("Interactive jumps ahead of queued background waiters on release")
    func interactiveJumpsAheadOfBackground() async {
        let gate = LiteRTSessionGate()

        // Interactive holds the session.
        #expect(await gate.acquire(priority: .interactive, preempt: noPreempt))

        let order = Order()

        // Queue a background waiter first, then an interactive waiter.
        let bg = Task {
            _ = await gate.acquire(priority: .background, preempt: noPreempt)
            await order.append("background")
        }
        try? await Task.sleep(for: .milliseconds(20))
        let fg = Task {
            _ = await gate.acquire(priority: .interactive, preempt: noPreempt)
            await order.append("interactive")
        }
        try? await Task.sleep(for: .milliseconds(20))

        // Release the holder: the interactive waiter must be served before the
        // earlier-queued background waiter.
        await gate.release()
        _ = await fg.value
        await gate.release()
        _ = await bg.value
        await gate.release()

        #expect(await order.items == ["interactive", "background"])
    }

    @Test("Cancelling a wait resolves false and doesn't consume the session")
    func cancellationResolvesFalse() async {
        let gate = LiteRTSessionGate()
        #expect(await gate.acquire(priority: .interactive, preempt: noPreempt))

        let waiter = Task {
            await gate.acquire(priority: .interactive, preempt: noPreempt)
        }
        try? await Task.sleep(for: .milliseconds(20))
        waiter.cancel()
        let result = await waiter.value
        #expect(!result)

        // The original holder still owns the session; a release frees it cleanly
        // and the next acquirer succeeds.
        await gate.release()
        #expect(await gate.acquire(priority: .background, preempt: noPreempt))
        await gate.release()
    }
}

private actor Preempted {
    private(set) var didFire = false
    func fire() {
        didFire = true
    }
}

private actor Order {
    private(set) var items: [String] = []
    func append(_ s: String) {
        items.append(s)
    }
}
