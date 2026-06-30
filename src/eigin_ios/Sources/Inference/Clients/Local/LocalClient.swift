import Foundation

struct LocalClient: LLMClient {
    func fetchModels() async throws -> [String] {
        var ready = [String]()
        if case .ready = await Self.appleFoundationModelStatus().state {
            ready.append("apple-foundation-model")
        }
        if case .ready = await Self.gemmaStatus().state {
            ready.append("gemma-4-e2b")
        }
        return ready
    }

    func validateAPIKey(model: String) async throws {}

    func chatCompletionStream(
        messages: [ChatMessage],
        model: String
    ) async throws -> AsyncThrowingStream<String, Error> {
        let eventStream = try await chatCompletionEventStream(
            messages: messages, model: model, tools: nil
        )
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await event in eventStream {
                        if case .contentDelta(let text) = event {
                            continuation.yield(text)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            // Propagate abandonment downward: dropping this string stream cancels
            // its consumption of the event stream, which in turn stops generation.
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func chatCompletionEventStream(
        messages: [ChatMessage],
        model: String,
        tools: [ToolDefinition]?,
        cacheKey _: String? = nil // Local models currently don't use cache keys.
    ) async throws -> AsyncThrowingStream<ChatStreamEvent, Error> {
        try await chatCompletionEventStream(
            messages: messages, model: model, tools: tools,
            cacheKey: nil, inlineToolRunner: nil
        )
    }

    func chatCompletionEventStream(
        messages: [ChatMessage],
        model: String,
        tools: [ToolDefinition]?,
        cacheKey _: String? = nil,
        inlineToolRunner: InlineToolRunner?
    ) async throws -> AsyncThrowingStream<ChatStreamEvent, Error> {
        if isApplePath(model: model) {
            try await appleEventStream(messages: messages, model: model, tools: tools)
        } else {
            try await gemmaEventStream(
                messages: messages, model: model, tools: tools,
                inlineToolRunner: inlineToolRunner
            )
        }
    }

    private func isApplePath(model: String) -> Bool {
        model == "apple-foundation-model"
    }
}

enum LocalClientError: LocalizedError {
    case modelNotLoaded
    case modelNotDownloaded
    case deviceUnsupported(detail: String)

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded: Localized.Model.notLoaded
        case .modelNotDownloaded: Localized.Model.notDownloaded
        case .deviceUnsupported: Localized.Model.insufficientRAM
        }
    }
}
