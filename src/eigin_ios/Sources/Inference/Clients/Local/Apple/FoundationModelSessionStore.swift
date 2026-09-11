import FoundationModels

/// Per-chat `LanguageModelSession` cache for the Apple foundation model.
@MainActor
final class FoundationModelSessionStore {
    static let shared = FoundationModelSessionStore()

    private var sessions: [String: LanguageModelSession] = [:]

    init() {}

    func hasSession(for chatKey: String) -> Bool {
        sessions[chatKey] != nil
    }

    func getOrCreate(
        chatKey: String,
        instructions: String?,
        tools: [any FoundationModels.Tool] = []
    ) -> LanguageModelSession {
        if let session = sessions[chatKey] {
            return session
        }
        let session = LanguageModelSession(tools: tools, instructions: instructions)
        sessions[chatKey] = session
        return session
    }

    func reset(chatKey: String) {
        sessions.removeValue(forKey: chatKey)
    }

    func reset() {
        sessions.removeAll()
    }
}
