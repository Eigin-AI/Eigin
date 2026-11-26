import EiginSDK
import Foundation

/// Leases one host iterator per read and releases it when the SDK cancels the candidate.
final class RequestEventCursor: @unchecked Sendable {
    private let lock = NSLock()
    private var iterator: AsyncThrowingStream<ChatStreamEvent, Error>.Iterator?
    private var cancelled = false

    init(_ stream: AsyncThrowingStream<ChatStreamEvent, Error>) {
        iterator = stream.makeAsyncIterator()
    }

    func next() async throws -> EiginSDK.Experimental.Inference.Event? {
        guard var iterator = lock.withLock({
            let value = self.iterator
            self.iterator = nil
            return value
        }) else { throw CancellationError() }
        defer {
            lock.withLock {
                if !cancelled { self.iterator = iterator }
            }
        }
        return try await iterator.next().map(InferenceSDKConversion.event)
    }

    func cancel() {
        let iterator = lock.withLock {
            cancelled = true
            let value = self.iterator
            self.iterator = nil
            return value
        }
        withExtendedLifetime(iterator) {}
    }
}
