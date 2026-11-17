import Foundation
import SwiftData

/// Resolves one watch chat per local calendar day.
///
/// Same-day questions share context. Previous chats remain available in the
/// phone's chat list.
///
/// The chat's identity lives in `UserDefaults` rather than in the SwiftData
/// schema, which keeps the watch out of a versioned, migration-bearing model.
/// Deleting the chat on the phone simply resets it.
enum WatchChat {
    /// Today's watch chat, creating it on the first request of the day.
    @MainActor
    static func resolve(
        in context: ModelContext, agentID: UUID,
        now: Date = .now, calendar: Calendar = .current
    ) -> Chat {
        if let existing = stored(in: context),
           calendar.isDate(existing.createdAt, inSameDayAs: now)
        {
            return existing
        }

        // Titled up front, so title generation has nothing to guess at and
        // the chat is easy to find in the phone's list.
        let chat = Chat(
            agentID: agentID, spaceID: nil, title: Localized.Watch.chatTitle
        )
        chat.createdAt = now
        chat.updatedAt = now
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
