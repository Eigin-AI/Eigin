@testable import Eigin
import Foundation

/// A fake ChatService that returns scripted ChatStreamEvent sequences for testing.
final class FakeChatService: ChatService, @unchecked Sendable {
    private let lock = NSLock()
    private var _eventSequences: [[[ChatStreamEvent]]] = []
    private var _callIndex = 0

    // Token stream support for chatCompletionStream
    private var _tokenSequences: [Result<[String], Error>] = []
    private var _tokenCallIndex = 0

    /// Captures messages passed to chatCompletionStream for inspection in tests
    private var _capturedMessages: [[ChatMessage]] = []

    /// All message arrays passed to ``chatCompletionStream``, in call order.
    var capturedMessages: [ChatMessage] {
        lock.withLock { _capturedMessages.last ?? [] }
    }

    /// Enqueue an event stream response. Each call to chatCompletionEventStream
    /// will consume the next sequence in order.
    func enqueueEventStream(_ events: [ChatStreamEvent]) {
        lock.withLock {
            _eventSequences.append([events])
        }
    }

    /// Enqueue multiple rounds of event streams (for tool call loops).
    func enqueueEventStreams(_ rounds: [[ChatStreamEvent]]) {
        lock.withLock {
            for round in rounds {
                _eventSequences.append([round])
            }
        }
    }

    /// Enqueue a token sequence for chatCompletionStream.
    func enqueueTokens(_ tokens: [String]) {
        lock.withLock {
            _tokenSequences.append(.success(tokens))
        }
    }

    /// Enqueue an error to throw during chatCompletionStream.
    func enqueueTokenError(_ error: Error) {
        lock.withLock {
            _tokenSequences.append(.failure(error))
        }
    }

    /// Error thrown by the next ``chatCompletionEventStream`` call, before the
    /// stream is returned. Mirrors how URLSession surfaces a request that fails
    /// (or is cancelled) at connection time rather than mid-stream.
    private var _eventStreamThrow: Error?

    /// Make the next ``chatCompletionEventStream`` call throw `error` directly.
    func throwOnEventStream(_ error: Error) {
        lock.withLock { _eventStreamThrow = error }
    }

    func chatCompletionStream(
        baseURL: String,
        providerID: UUID,
        messages: [ChatMessage],
        model: String
    ) async throws -> AsyncThrowingStream<String, Error> {
        lock.withLock { _capturedMessages.append(messages) }
        let entry: Result<[String], Error> = lock.withLock {
            if _tokenCallIndex < _tokenSequences.count {
                let e = _tokenSequences[_tokenCallIndex]
                _tokenCallIndex += 1
                return e
            } else {
                return .success([])
            }
        }

        return AsyncThrowingStream { continuation in
            Task {
                switch entry {
                case .success(let tokens):
                    for token in tokens {
                        continuation.yield(token)
                    }
                    continuation.finish()
                case .failure(let error):
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func chatCompletionEventStream(
        baseURL: String,
        providerID: UUID,
        messages: [ChatMessage],
        model: String,
        tools: [ToolDefinition]?,
        cacheKey _: String?
    ) async throws -> AsyncThrowingStream<ChatStreamEvent, Error> {
        if let thrown: Error = lock.withLock({
            let e = _eventStreamThrow
            _eventStreamThrow = nil
            return e
        }) {
            throw thrown
        }

        let events: [ChatStreamEvent] = lock.withLock {
            if _callIndex < _eventSequences.count {
                let e = _eventSequences[_callIndex].first ?? []
                _callIndex += 1
                return e
            } else {
                return [.finished(.stop)]
            }
        }

        return AsyncThrowingStream { continuation in
            Task {
                for event in events {
                    continuation.yield(event)
                }
                continuation.finish()
            }
        }
    }
}
