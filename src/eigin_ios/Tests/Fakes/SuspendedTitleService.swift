@testable import Eigin
import Foundation

/// Holds title responses until a test explicitly finishes each request.
actor SuspendedTitleService: ChatService {
    private(set) var requestCount = 0
    private var response: AsyncThrowingStream<String, Error>.Continuation?
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func waitForRequest(_ count: Int = 1) async {
        guard requestCount < count else { return }
        await withCheckedContinuation { waiters.append((count, $0)) }
    }

    func finish(_ title: String) {
        response?.yield(title)
        response?.finish()
        response = nil
    }

    func chatCompletionStream(
        baseURL: String, providerID: UUID, messages: [ChatMessage], model: String
    ) async throws -> AsyncThrowingStream<String, Error> {
        let (stream, continuation) = AsyncThrowingStream<String, Error>.makeStream()
        response = continuation
        requestCount += 1
        let ready = waiters.filter { $0.0 <= requestCount }
        waiters.removeAll { $0.0 <= requestCount }
        for (_, waiter) in ready {
            waiter.resume()
        }
        return stream
    }

    func chatCompletionEventStream(
        baseURL: String, providerID: UUID, messages: [ChatMessage], model: String,
        tools: [ToolDefinition]?, cacheKey: String?
    ) async throws -> AsyncThrowingStream<ChatStreamEvent, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}
