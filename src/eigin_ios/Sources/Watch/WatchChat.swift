import Foundation
import SwiftData

/// Resolves the single long-lived chat that watch-triggered questions continue.
///
/// Context carries across wrist taps: every question joins the same
/// conversation, so a follow-up knows what the last one was about. The chat is
/// visible in the phone's chat list — ask on the wrist, continue on the phone.
///
/// The chat's identity lives in `UserDefaults` rather than in the SwiftData
/// schema, which keeps the watch out of a versioned, migration-bearing model.
/// Deleting the chat on the phone simply resets it.
enum WatchChat {
    /// The watch chat, creating and persisting it on first use.
    @MainActor
    static func resolve(in context: ModelContext, agentID: UUID) -> Chat {
        if let existing = stored(in: context) { return existing }

        // Titled up front, so title generation has nothing to guess at and
        // the chat is easy to find in the phone's list.
        let chat = Chat(
            agentID: agentID, spaceID: nil, title: Localized.Watch.chatTitle
        )
        context.insert(chat)
        UserDefaults.standard.set(chat.id.uuidString, forKey: StorageKey.watchChat)
        return chat
    }

    /// The stored chat, or nil when none was created yet or the user deleted it.
    @MainActor
    private static func stored(in context: ModelContext) -> Chat? {
        guard let raw = UserDefaults.standard.string(forKey: StorageKey.watchChat),
              let id = UUID(uuidString: raw)
        else { return nil }

        var descriptor = FetchDescriptor<Chat>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    /// The stored chat's id, or nil when none was created yet. Reads the
    /// UserDefaults key directly, so callers outside a model context — the
    /// notification, for one — can route to the chat without a fetch.
    static func storedID() -> UUID? {
        guard let raw = UserDefaults.standard.string(forKey: StorageKey.watchChat) else {
            return nil
        }
        return UUID(uuidString: raw)
    }
}
