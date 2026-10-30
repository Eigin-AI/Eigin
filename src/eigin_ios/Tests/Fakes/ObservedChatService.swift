@testable import Eigin
import Foundation
import os

/// Observes model requests while forwarding scripted responses to the real loop.
final class ObservedChatService: ChatService, @unchecked Sendable {
    let scripted = FakeChatService()
    private let requestCount = OSAllocatedUnfairLock(initialState: 0)
    private let observe: @MainActor @Sendable (Int, [ChatMessage], [ToolDefinition]) -> Void

    init(observe: @escaping @MainActor @Sendable (Int, [ChatMessage], [ToolDefinition]) -> Void) {
        self.observe = observe
    }

    func chatCompletionStream(
        baseURL: String,
        providerID: UUID,
        messages: [ChatMessage],
        model: String
    ) async throws -> AsyncThrowingStream<String, Error> {
        try await scripted.chatCompletionStream(
            baseURL: baseURL,
            providerID: providerID,
            messages: messages,
            model: model
        )
    }

    func chatCompletionEventStream(
        baseURL: String,
        providerID: UUID,
        messages: [ChatMessage],
        model: String,
        tools: [ToolDefinition]?,
        cacheKey: String?
    ) async throws -> AsyncThrowingStream<ChatStreamEvent, Error> {
        let index = requestCount.withLock { count in
            defer { count += 1 }
            return count
        }
        await observe(index, messages, tools ?? [])
        return try await scripted.chatCompletionEventStream(
            baseURL: baseURL, providerID: providerID, messages: messages, model: model,
            tools: tools, cacheKey: cacheKey
        )
    }
}
