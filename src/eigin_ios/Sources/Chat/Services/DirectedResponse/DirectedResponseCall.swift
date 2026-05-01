import Foundation

/// Streams a response using a stage-specific system prompt and conversation history.
///
/// Intentionally thin — the caller owns prompt construction (injecting collected data,
/// directives, language preferences). This just handles "system prompt + history → stream."
struct DirectedResponseCall {
    let chatService: ChatService

    /// Streams a visible response directed by the given system prompt.
    ///
    /// - Parameters:
    ///   - systemPrompt: Stage-specific instructions for the model, including any
    ///     collected data and directive for what to ask or do next.
    ///   - conversationHistory: Previous messages in the conversation, displayed to the user.
    ///   - baseURL: Provider base URL.
    ///   - providerID: Provider UUID for keychain key resolution.
    ///   - model: Model identifier string.
    /// - Returns: A stream of text deltas suitable for display in the chat UI.
    func stream(
        systemPrompt: String,
        conversationHistory: [ChatMessage],
        baseURL: String,
        providerID: UUID,
        model: String
    ) async throws -> AsyncThrowingStream<String, Error> {
        var messages = [ChatMessage(role: "system", content: systemPrompt)]
        messages.append(contentsOf: conversationHistory)
        return try await chatService.chatCompletionStream(
            baseURL: baseURL,
            providerID: providerID,
            messages: messages,
            model: model
        )
    }
}
