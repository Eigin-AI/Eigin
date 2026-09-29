#if DEBUG || EIGIN_DEV
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

    /// Captures message arrays passed to ``chatCompletionEventStream``, in call order.
    private var _capturedEventMessages: [[ChatMessage]] = []

    /// Message array from the most recent ``chatCompletionEventStream`` call.
    var capturedEventMessages: [ChatMessage] {
        lock.withLock { _capturedEventMessages.last ?? [] }
    }

    private var _capturedEventTools: [ToolDefinition]?
    private var _capturedEventCacheKey: String?

    /// Tools and cache key from the most recent ``chatCompletionEventStream`` call.
    var capturedEventTools: [ToolDefinition]? {
        lock.withLock { _capturedEventTools }
    }

    var capturedEventCacheKey: String? {
        lock.withLock { _capturedEventCacheKey }
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

    /// Delay before the stream returns, mimicking a provider holding the response.
    private var _preStreamDelay: Duration = .zero

    /// Make ``chatCompletionEventStream`` wait `delay` before returning the stream.
    func delayBeforeStream(_ delay: Duration) {
        lock.withLock { _preStreamDelay = delay }
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
        cacheKey: String?
    ) async throws -> AsyncThrowingStream<ChatStreamEvent, Error> {
        try await chatCompletionEventStream(
            baseURL: baseURL, providerID: providerID, messages: messages,
            model: model, tools: tools, cacheKey: cacheKey, inlineToolRunner: nil
        )
    }

    /// Captures the inline runner passed by the loop so tests can inspect or invoke it.
    private(set) var capturedInlineRunner: InlineToolRunner?

    /// Scripted inline tool calls to execute using the captured runner before yielding prose.
    private var _inlineToolCalls: [ToolCall] = []

    /// Queue scripted inline tool calls. The fake will invoke the runner for each
    /// and emit only prose + .finished(.stop) to simulate a local model.
    func enqueueInlineToolCalls(_ calls: [ToolCall]) {
        lock.withLock { _inlineToolCalls = calls }
    }

    /// The model of the most recent request, for asserting which one the loop used.
    var lastModel: String? {
        lock.withLock { _lastModel }
    }

    private var _lastModel: String?

    func chatCompletionEventStream(
        baseURL: String,
        providerID: UUID,
        messages: [ChatMessage],
        model: String,
        tools: [ToolDefinition]?,
        cacheKey: String?,
        inlineToolRunner: InlineToolRunner?
    ) async throws -> AsyncThrowingStream<ChatStreamEvent, Error> {
        lock.withLock {
            _lastModel = model
            _capturedEventMessages.append(messages)
            _capturedEventTools = tools
            _capturedEventCacheKey = cacheKey
        }
        let preStreamDelay = lock.withLock { _preStreamDelay }
        if preStreamDelay > .zero {
            try await Task.sleep(for: preStreamDelay)
        }
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

        // Capture the runner for test inspection.
        lock.withLock { capturedInlineRunner = inlineToolRunner }

        // Inline tool calls: invoke the runner mid-stream (before prose), then
        // yield prose-only events. This simulates a local model executing tools
        // internally before producing its final response.
        let inlineCalls = lock.withLock { _inlineToolCalls }

        return AsyncThrowingStream { continuation in
            Task { @MainActor in
                // Execute inline tool calls through the runner, like a local model would.
                for call in inlineCalls {
                    if let runner = inlineToolRunner {
                        _ = await runner.run(call)
                    }
                }
                // Yield the scripted prose events (caller should queue .contentDelta +
                // .finished(.stop)).
                for event in events {
                    continuation.yield(event)
                }
                continuation.finish()
            }
        }
    }
}
#endif
