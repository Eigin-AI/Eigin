import Foundation

/// Requires a later user message before a skill can present a connection sheet.
@MainActor final class SkillConnectionGate {
    enum Decision {
        case askUser
        case waitForUser
        case connect(UUID)
    }

    private struct Key: Hashable {
        let chatID: UUID
        let skillID: String
    }

    private struct Entry {
        let missing: Set<Capability>
        let messageID: String
        var attempt: UUID?
        var finished = false
    }

    private var messages: [UUID: String] = [:]
    private var entries: [Key: Entry] = [:]

    /// Advances only when an actual user message is accepted.
    func beginUserTurn(chatID: UUID, messageID: String) {
        messages[chatID] = messageID
    }

    /// The boundary captured by a tool instance, including registry rebuilds.
    func messageID(chatID: UUID) -> String? {
        messages[chatID]
    }

    /// Reserves a single presentation; stale tools and concurrent retries fail closed.
    func request(
        chatID: UUID,
        skillID: String,
        missing: Set<Capability>,
        messageID: String?
    ) -> Decision {
        guard let messageID, messages[chatID] == messageID else { return .waitForUser }
        let key = Key(chatID: chatID, skillID: skillID)
        if var entry = entries[key] {
            if entry.attempt != nil, !entry.finished { return .waitForUser }
            if entry.finished, entry.messageID == messageID { return .waitForUser }
            if !entry.finished, entry.missing == missing {
                guard entry.messageID != messageID else { return .waitForUser }
                let attempt = UUID()
                entry = Entry(missing: missing, messageID: messageID, attempt: attempt)
                entries[key] = entry
                return .connect(attempt)
            }
        }
        entries[key] = Entry(missing: missing, messageID: messageID)
        return .askUser
    }

    /// Finishes only the reserved attempt, retaining same-turn retry suppression.
    func finish(chatID: UUID, skillID: String, attempt: UUID) {
        let key = Key(chatID: chatID, skillID: skillID)
        guard entries[key]?.attempt == attempt else { return }
        entries[key]?.finished = true
    }

    /// Removes pending state when the skill's capabilities are available.
    func clear(chatID: UUID, skillID: String) {
        entries.removeValue(forKey: Key(chatID: chatID, skillID: skillID))
    }
}
