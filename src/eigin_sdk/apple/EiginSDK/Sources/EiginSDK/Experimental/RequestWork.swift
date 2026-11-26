import Foundation

/// Serializes task installation with cancellation without invoking callbacks under its lock.
final class RequestWork: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var task: Task<Void, Never>?

    func launch(
        onCancelled: @Sendable () -> Void = {},
        _ body: @escaping @Sendable () async -> Void
    ) {
        let launched = lock.withLock {
            guard !cancelled else { return false }
            task = Task { await body() }
            return true
        }
        if !launched { onCancelled() }
    }

    func cancel() {
        let task = lock.withLock {
            cancelled = true
            let value = self.task
            self.task = nil
            return value
        }
        task?.cancel()
    }
}

/// Rejects sessions returned by an opener after its candidate was cancelled.
final class RequestSessionSlot: @unchecked Sendable {
    private typealias Session = EiginSDK.Experimental.Inference.RequestSession
    private let lock = NSLock()
    private var cancelled = false
    private var session: Session?

    func install(_ session: EiginSDK.Experimental.Inference.RequestSession) -> Bool {
        let accepted = lock.withLock {
            guard !cancelled else { return false }
            self.session = session
            return true
        }
        if !accepted { session.cancel() }
        return accepted
    }

    func next() async throws -> EiginSDK.Experimental.Inference.Event? {
        guard let session = lock.withLock({ session }) else { throw CancellationError() }
        return try await session.next()
    }

    func cancel() {
        let session = lock.withLock {
            cancelled = true
            let value = self.session
            self.session = nil
            return value
        }
        session?.cancel()
    }
}
