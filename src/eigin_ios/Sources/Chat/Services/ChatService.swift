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
        tools: [ToolDefinition]?
    ) async throws -> AsyncThrowingStream<ChatStreamEvent, Error>
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
        let apiKey: String
        if ProviderPreset.isLocal(baseURL) {
            apiKey = ""
        } else {
            guard let key = keychainService.read(key: keychainService.providerKey(for: providerID))
            else {
                AppLogger.error(
                    "API key not found for provider \(public: providerID)",
                    category: .chat
                )
                throw ChatServiceError.apiKeyNotFound
            }
            apiKey = key
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
        tools: [ToolDefinition]?
    ) async throws -> AsyncThrowingStream<ChatStreamEvent, Error> {
        let apiKey: String
        if ProviderPreset.isLocal(baseURL) {
            apiKey = ""
        } else {
            guard let key = keychainService.read(key: keychainService.providerKey(for: providerID))
            else {
                AppLogger.error(
                    "API key not found for provider \(public: providerID)",
                    category: .chat
                )
                throw ChatServiceError.apiKeyNotFound
            }
            apiKey = key
        }
        let client = LLMClientFactory.client(baseURL: baseURL, apiToken: apiKey)
        return try await withRetry {
            try await client.chatCompletionEventStream(
                messages: messages,
                model: model,
                tools: tools
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

/// Fake implementation that streams a canned response word-by-word for previews and testing.
struct PreviewChatService: ChatService {
    var cannedResponse: String = "This is a sample response from the fake provider. It streams word by word to simulate a real completion."

    func chatCompletionStream(
        baseURL: String,
        providerID: UUID,
        messages: [ChatMessage],
        model: String
    ) async throws -> AsyncThrowingStream<String, Error> {
        let words = cannedResponse.split(separator: " ")
        return AsyncThrowingStream { continuation in
            Task {
                for (index, word) in words.enumerated() {
                    try await Task.sleep(for: .milliseconds(60))
                    let token = (index == 0 ? "" : " ") + word
                    continuation.yield(String(token))
                }
                continuation.finish()
            }
        }
    }

    func chatCompletionEventStream(
        baseURL: String,
        providerID: UUID,
        messages: [ChatMessage],
        model: String,
        tools: [ToolDefinition]?
    ) async throws -> AsyncThrowingStream<ChatStreamEvent, Error> {
        let words = cannedResponse.split(separator: " ")
        return AsyncThrowingStream { continuation in
            Task {
                for (index, word) in words.enumerated() {
                    try await Task.sleep(for: .milliseconds(60))
                    let token = (index == 0 ? "" : " ") + word
                    continuation.yield(.contentDelta(String(token)))
                }
                continuation.yield(.finished(.stop))
                continuation.finish()
            }
        }
    }
}

/// Streams a scripted response with a configurable thinking delay,
/// simulating a real model response through the same pipeline.
struct ScriptedChatService: ChatService {
    let text: String
    let thinkingDelay: Duration

    init(text: String, thinkingDelay: Duration = .milliseconds(750)) {
        self.text = text
        self.thinkingDelay = thinkingDelay
    }

    func chatCompletionStream(
        baseURL: String,
        providerID: UUID,
        messages: [ChatMessage],
        model: String
    ) async throws -> AsyncThrowingStream<String, Error> {
        let words = text.split(separator: " ")
        return AsyncThrowingStream { continuation in
            Task {
                try await Task.sleep(for: thinkingDelay)
                for (index, word) in words.enumerated() {
                    try await Task.sleep(for: .milliseconds(30))
                    let token = (index == 0 ? "" : " ") + word
                    continuation.yield(String(token))
                }
                continuation.finish()
            }
        }
    }

    func chatCompletionEventStream(
        baseURL: String,
        providerID: UUID,
        messages: [ChatMessage],
        model: String,
        tools: [ToolDefinition]?
    ) async throws -> AsyncThrowingStream<ChatStreamEvent, Error> {
        let words = text.split(separator: " ")
        return AsyncThrowingStream { continuation in
            Task {
                try await Task.sleep(for: thinkingDelay)
                for (index, word) in words.enumerated() {
                    try await Task.sleep(for: .milliseconds(30))
                    let token = (index == 0 ? "" : " ") + word
                    continuation.yield(.contentDelta(String(token)))
                }
                continuation.yield(.finished(.stop))
                continuation.finish()
            }
        }
    }
}

enum ChatServiceError: LocalizedError {
    case apiKeyNotFound

    var errorDescription: String? {
        switch self {
        case .apiKeyNotFound: "API key not found in Keychain."
        }
    }
}
