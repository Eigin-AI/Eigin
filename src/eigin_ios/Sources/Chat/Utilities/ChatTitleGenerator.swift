import Foundation
import SwiftData

/// Handles automatic title generation and seeding for chats.
@MainActor
enum ChatTitleGenerator {
    /// Minimum number of assistant messages before auto-generating a title.
    static let titleGenerationThreshold = 4

    /// Generates a title only while the chat exists and still permits automatic titles.
    @discardableResult
    static func generate(
        chatID: UUID,
        context: ModelContext,
        messages: [ChatMessage],
        agent: Agent,
        provider: Provider,
        model: String? = nil,
        chatService: any ChatService,
        using overrideMessages: [ChatMessage]? = nil
    ) -> Task<Void, Never>? {
        guard eligibleChat(chatID, in: context) != nil else { return nil }

        let conversationSummary = (overrideMessages ?? messages)
            .filter { $0.role == "user" || $0.role == "assistant" }
            .compactMap(\.content)
            .map { ChatTags.stripAll(from: $0) }
            .prefix(6)
            .joined(separator: "\n")
        let baseURL = provider.baseURL
        let providerID = provider.id
        let requestModel = model ?? agent.model

        return Task {
            for attempt in 0 ... 1 {
                guard !Task.isCancelled, eligibleChat(chatID, in: context) != nil else { return }
                let prompt = (attempt == 0 ? Prompt.Title.first : Prompt.Title.retry)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let titleMessages = [
                    ChatMessage(role: "system", content: prompt),
                    ChatMessage(role: "user", content: conversationSummary),
                ]
                var title = ""
                do {
                    // Best-effort background work: a foreground chat send preempts it.
                    try await LocalGeneration.$priority.withValue(.background) {
                        let stream = try await chatService.chatCompletionStream(
                            baseURL: baseURL, providerID: providerID,
                            messages: titleMessages, model: requestModel
                        )
                        for try await token in stream {
                            title += token
                        }
                    }
                    guard !Task.isCancelled,
                          let chat = eligibleChat(chatID, in: context) else { return }
                    if let cleaned = cleanTitle(title) {
                        chat.title = cleaned
                        chat.titleOrigin = .generated
                        chat.updatedAt = .now
                        return
                    }
                } catch {
                    // Title generation is non-critical — fail silently.
                    return
                }
            }
        }
    }

    private static func eligibleChat(_ id: UUID, in context: ModelContext) -> Chat? {
        guard let chat = ChatLookup.find(id, in: context),
              chat.titleOrigin != .generated, chat.titleOrigin != .edited else { return nil }
        return chat
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
