import Foundation

/// Serializes native generation and scopes the tool runner to the active request.
final class GemmaGenerationSession: Sendable {
    private let gate = LiteRTSessionGate()

    func stream(
        runner: InlineToolRunner?,
        generate: @escaping @Sendable (AsyncStream<String>.Continuation) async -> Void
    ) -> AsyncStream<String> {
        let (stream, continuation) = AsyncStream<String>.makeStream()
        let priority = LocalGeneration.priority
        let cancellation = GemmaGenerationCancellation()
        let task = Task {
            let acquired = await gate.acquire(priority: priority) { cancellation.cancel() }
            if acquired {
                GemmaToolBridgeRunner.current = runner
                if !Task.isCancelled { await generate(continuation) }
                GemmaToolBridgeRunner.current = nil
                await gate.release()
            }
            continuation.finish()
        }
        cancellation.install(task)
        continuation.onTermination = { _ in cancellation.cancel() }
        return stream
    }
}

/// Remembers cancellation that arrives before the worker handle is installed.
private final class GemmaGenerationCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var task: Task<Void, Never>?

    func install(_ task: Task<Void, Never>) {
        let cancelled = lock.withLock {
            self.task = task
            return self.cancelled
        }
        if cancelled { task.cancel() }
    }

    func cancel() {
        let task = lock.withLock {
            cancelled = true
            return self.task
        }
        task?.cancel()
    }
}
