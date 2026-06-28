import Foundation

/// Handles automatic title generation and seeding for chats.
@MainActor
enum ChatTitleGenerator {
    /// Minimum number of assistant messages before auto-generating a title.
    static let titleGenerationThreshold = 4

    /// Generates a title by sending the conversation summary to the LLM.
    static func generate(
        chat: Chat,
        messages: [ChatMessage],
        agent: Agent,
        provider: Provider,
        chatService: any ChatService,
        retryCount: Int = 0,
        using overrideMessages: [ChatMessage]? = nil
    ) {
        guard chat.titleOrigin != .generated, chat.titleOrigin != .edited else { return }

        let source = overrideMessages ?? messages
        let conversationSummary = source
            .filter { $0.role == "user" || $0.role == "assistant" }
            .compactMap(\.content)
            .map { ChatTags.stripAll(from: $0) }
            .prefix(6)
            .joined(separator: "\n")

        let prompt = (retryCount == 0 ? Prompt.Title.first : Prompt.Title.retry)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let titleMessages: [ChatMessage] = [
            ChatMessage(role: "system", content: prompt),
            ChatMessage(role: "user", content: conversationSummary),
        ]

        Task {
            var title = ""
            let stream = try await chatService.chatCompletionStream(
                baseURL: provider.baseURL,
                providerID: provider.id,
                messages: titleMessages,
                model: agent.model
            )
            do {
                for try await token in stream {
                    title += token
                }
                let cleaned = cleanTitle(title)
                if let cleaned {
                    chat.title = cleaned
                    chat.titleOrigin = .generated
                    chat.updatedAt = .now
                } else if retryCount == 0 {
                    generate(
                        chat: chat, messages: messages,
                        agent: agent, provider: provider,
                        chatService: chatService,
                        retryCount: 1, using: overrideMessages
                    )
                }
            } catch {
                // Title generation is non-critical — fail silently
            }
        }
    }

    /// Seeds the chat title from the first sentence of the user's message.
    static func seed(chat: Chat, from content: String) {
        guard chat.title.isEmpty else { return }
        let stripped = ChatTags.stripAll(from: content)
        let firstSentence = stripped
            .components(separatedBy: CharacterSet(charactersIn: ".?!\n"))
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let cleaned = cleanTitle(firstSentence) else { return }
        chat.title = cleaned
        chat.titleOrigin = .seeded
        chat.updatedAt = .now
    }

    /// Cleans a raw title string: strips quotes, trims, and truncates to 40 chars.
    nonisolated static func cleanTitle(_ raw: String) -> String? {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if (t.hasPrefix("\"") && t.hasSuffix("\"")) || (t.hasPrefix("'") && t.hasSuffix("'")) {
            t = String(t.dropFirst().dropLast())
            t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !t.isEmpty else { return nil }
        if t.count > 40 {
            let prefix = t.prefix(40)
            if let lastSpace = prefix.lastIndex(of: " ") {
                t = String(prefix[prefix.startIndex ..< lastSpace])
            } else {
                t = String(prefix)
            }
        }
        return t.isEmpty ? nil : t
    }
}
