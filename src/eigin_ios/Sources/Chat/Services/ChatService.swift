import Foundation

/// Abstraction over chat completion streaming, allowing real and fake implementations.
protocol ChatService: Sendable {
    func chatCompletionStream(
        baseURL: String,
        providerID: UUID,
        messages: [ChatMessage],
        model: String
    ) async throws -> AsyncThrowingStream<String, Error>

    func chatCompletionEventStream(
        baseURL: String,
        providerID: UUID,
        messages: [ChatMessage],
        model: String,
        tools: [ToolDefinition]?,
        cacheKey: String?
    ) async throws -> AsyncThrowingStream<ChatStreamEvent, Error>

    /// Variant for local models: passes an ``InlineToolRunner`` so the
    /// runtime can execute tools mid-stream without the chat loop needing
    /// any provider-specific branching. Cloud implementations forward to the
    /// standard method and ignore the runner.
    func chatCompletionEventStream(
        baseURL: String,
        providerID: UUID,
        messages: [ChatMessage],
        model: String,
        tools: [ToolDefinition]?,
        cacheKey: String?,
        inlineToolRunner: InlineToolRunner?
    ) async throws -> AsyncThrowingStream<ChatStreamEvent, Error>
}

extension ChatService {
    /// Default implementation: ignores the runner and forwards to the
    /// standard method. Cloud providers adopt this automatically.
    func chatCompletionEventStream(
        baseURL: String,
        providerID: UUID,
        messages: [ChatMessage],
        model: String,
        tools: [ToolDefinition]?,
        cacheKey: String?,
        inlineToolRunner _: InlineToolRunner?
    ) async throws -> AsyncThrowingStream<ChatStreamEvent, Error> {
        try await chatCompletionEventStream(
            baseURL: baseURL,
            providerID: providerID,
            messages: messages,
            model: model,
            tools: tools,
            cacheKey: cacheKey
        )
    }
}

/// Implementation that uses ``LLMClientFactory`` to pick the right client for each provider.
struct DefaultChatService: ChatService {
    let keychainService: KeychainService

    func chatCompletionStream(
        baseURL: String,
        providerID: UUID,
        messages: [ChatMessage],
        model: String
    ) async throws -> AsyncThrowingStream<String, Error> {
        guard let apiKey = ProviderCredentials.apiToken(
            baseURL: baseURL, providerID: providerID, keychain: keychainService
        ) else {
            AppLogger.error(
                "API key not found for provider \(public: providerID)",
                category: .chat
            )
            throw ChatServiceError.apiKeyNotFound
        }
        let client = LLMClientFactory.client(baseURL: baseURL, apiToken: apiKey)
        return try await withRetry {
            try await client.chatCompletionStream(messages: messages, model: model)
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
            baseURL: baseURL,
            providerID: providerID,
            messages: messages,
            model: model,
            tools: tools,
            cacheKey: cacheKey,
            inlineToolRunner: nil
        )
    }

    func chatCompletionEventStream(
        baseURL: String,
        providerID: UUID,
        messages: [ChatMessage],
        model: String,
        tools: [ToolDefinition]?,
        cacheKey: String?,
        inlineToolRunner: InlineToolRunner?
    ) async throws -> AsyncThrowingStream<ChatStreamEvent, Error> {
        guard let apiKey = ProviderCredentials.apiToken(
            baseURL: baseURL, providerID: providerID, keychain: keychainService
        ) else {
            AppLogger.error(
                "API key not found for provider \(public: providerID)",
                category: .chat
            )
            throw ChatServiceError.apiKeyNotFound
        }
        let client = LLMClientFactory.client(baseURL: baseURL, apiToken: apiKey)
        // Local client: forward the runner so the runtime can execute tools inline.
        if let localClient = client as? LocalClient {
            return try await withRetry {
                try await localClient.chatCompletionEventStream(
                    messages: messages,
                    model: model,
                    tools: tools,
                    cacheKey: cacheKey,
                    inlineToolRunner: inlineToolRunner
                )
            }
        }
        // Cloud clients: runner is irrelevant.
        return try await withRetry {
            try await client.chatCompletionEventStream(
                messages: messages,
                model: model,
                tools: tools,
                cacheKey: cacheKey
            )
        }
    }
}

// MARK: - Retry

private func isRetryable(_ error: Error) -> Bool {
    if let clientError = error as? OpenAICompatibleClientError {
        switch clientError {
        case .httpError(let code, _):
            return code == 429 || (500 ... 599).contains(code)
        case .invalidURL, .invalidResponse:
            return false
        }
    }
    if let urlError = error as? URLError {
        switch urlError.code {
        case .timedOut, .networkConnectionLost:
            return true
        default:
            return false
        }
    }
    return false
}

/// Retries the connection phase of a stream factory on transient errors.
///
/// Only the `makeStream` call (which establishes the HTTP connection) is retried.
/// Once a stream is returned, any errors during SSE parsing are not retried.
func withRetry<T: Sendable>(
    maxAttempts: Int = 3,
    makeStream: @escaping @Sendable () async throws -> AsyncThrowingStream<T, Error>
) async throws -> AsyncThrowingStream<T, Error> {
    for attempt in 1 ... maxAttempts {
        do {
            return try await makeStream()
        } catch {
            if isRetryable(error), attempt < maxAttempts {
                let delay = UInt64(pow(2.0, Double(attempt - 1)))
                AppLogger.warning(
                    "Retryable error (attempt \(public: attempt)/\(public: maxAttempts)): \(private: error.localizedDescription). Retrying in \(public: delay)s…",
                    category: .network
                )
                try await Task.sleep(for: .seconds(delay))
                continue
            }
            throw error
        }
    }
    fatalError("unreachable")
}
