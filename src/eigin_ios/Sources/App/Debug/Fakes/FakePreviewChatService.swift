import Foundation

/// Fake implementation that streams a canned response word-by-word for
/// previews and testing. Extracted from \`ChatService\` (issue #228: every
/// fake lives in one folder).
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
        tools: [ToolDefinition]?,
        cacheKey _: String?
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
        tools: [ToolDefinition]?,
        cacheKey _: String?
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
