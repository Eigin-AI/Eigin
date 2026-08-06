import Foundation
import os

/// Thrown when a stream produces nothing before its deadline.
struct FirstEventTimeout: Error {}

/// Fails a stream that produces nothing within `deadline`.
///
/// A model that has sent no first token in half a minute is indistinguishable from a
/// hang, and waiting longer serves nobody. Once the first event lands the deadline is
/// done: a slow-but-working stream is a health signal, not a failure.
///
/// Skip this for on-device models, where a long prefill is normal and there is nothing
/// left to fall back to anyway.
func withFirstEventDeadline<T: Sendable>(
    _ stream: AsyncThrowingStream<T, Error>,
    deadline: Duration
) -> AsyncThrowingStream<T, Error> {
    AsyncThrowingStream { continuation in
        let state = DeadlineState()

        let forwarding = Task {
            do {
                for try await element in stream {
                    state.markFirstEvent()
                    continuation.yield(element)
                }
                state.cancelWatchdog()
                continuation.finish()
            } catch {
                state.cancelWatchdog()
                continuation.finish(throwing: error)
            }
        }

        state.setWatchdog(
            Task {
                try? await Task.sleep(for: deadline)
                guard !Task.isCancelled, !state.sawFirstEvent else { return }
                forwarding.cancel()
                continuation.finish(throwing: FirstEventTimeout())
            }
        )

        continuation.onTermination = { _ in
            forwarding.cancel()
            state.cancelWatchdog()
        }
    }
}

/// Shared state between the forwarding task and its watchdog.
private final class DeadlineState: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(
        initialState: (watchdog: Task<Void, Never>?.none, sawFirstEvent: false)
    )

    var sawFirstEvent: Bool {
        lock.withLock { $0.sawFirstEvent }
    }

    func setWatchdog(_ task: Task<Void, Never>) {
        // The first event can land before the watchdog is stored, so cancel immediately
        // rather than leaving a task nothing will ever stop.
        let alreadyStarted = lock.withLock { state -> Bool in
            guard !state.sawFirstEvent else { return true }
            state.watchdog = task
            return false
        }
        if alreadyStarted { task.cancel() }
    }

    func markFirstEvent() {
        let watchdog = lock.withLock { state -> Task<Void, Never>? in
            guard !state.sawFirstEvent else { return nil }
            state.sawFirstEvent = true
            defer { state.watchdog = nil }
            return state.watchdog
        }
        watchdog?.cancel()
    }

    func cancelWatchdog() {
        let watchdog = lock.withLock { state -> Task<Void, Never>? in
            defer { state.watchdog = nil }
            return state.watchdog
        }
        watchdog?.cancel()
    }
}
