import Foundation

/// Serializes access to the single LiteRT engine session.
///
/// LiteRT-LM allows only one active session per engine, so all generation must
/// run one at a time — concurrent attempts fail with
/// `FAILED_PRECONDITION: A session already exists`. This gate enforces that, and
/// gives foreground work priority: an `.interactive` acquirer preempts a running
/// `.background` holder and cancels any queued background waiters, so chat is
/// never blocked behind compaction or title generation.
actor LiteRTSessionGate {
    private struct Waiter {
        let id: UUID
        let priority: LocalGenerationPriority
        let preempt: @Sendable () -> Void
        let continuation: CheckedContinuation<Bool, Never>
    }

    private var holder: (priority: LocalGenerationPriority, preempt: @Sendable () -> Void)?
    private var waiters: [Waiter] = []

    /// Wait for exclusive access to the session.
    ///
    /// - Parameter preempt: Called if a higher-priority acquirer needs this
    ///   request to yield. It should cancel the in-flight generation so the
    ///   holder reaches ``release()`` promptly.
    /// - Returns: `true` once access is held — the caller must then call
    ///   ``release()``. `false` if the wait was cancelled before access was
    ///   granted, in which case the caller must not call ``release()``.
    func acquire(
        priority: LocalGenerationPriority,
        preempt: @escaping @Sendable () -> Void
    ) async -> Bool {
        if holder == nil {
            holder = (priority, preempt)
            return true
        }

        // Foreground work preempts a running background holder and any queued
        // background waiters so it runs as soon as the holder yields.
        if priority == .interactive {
            if holder?.priority == .background {
                holder?.preempt()
            }
            for waiter in waiters where waiter.priority == .background {
                waiter.preempt()
            }
        }

        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                if Task.isCancelled {
                    continuation.resume(returning: false)
                    return
                }
                waiters.append(
                    Waiter(id: id, priority: priority, preempt: preempt, continuation: continuation)
                )
            }
        } onCancel: {
            Task { await self.cancelWait(id) }
        }
    }

    /// Release access held after a successful ``acquire(priority:preempt:)``,
    /// handing the session to the highest-priority waiter (interactive first,
    /// FIFO within a priority).
    func release() {
        guard !waiters.isEmpty else {
            holder = nil
            return
        }
        let index = waiters.firstIndex { $0.priority == .interactive } ?? 0
        let next = waiters.remove(at: index)
        holder = (next.priority, next.preempt)
        next.continuation.resume(returning: true)
    }

    private func cancelWait(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        let waiter = waiters.remove(at: index)
        waiter.continuation.resume(returning: false)
    }
}
