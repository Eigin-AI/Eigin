import Foundation

/// Decides which chats appear in the list.
///
/// Keeps private-space discretion out of the view: when no space is selected,
/// chats in private spaces are hidden so they don't surface in the default list.
/// They stay reachable by explicitly selecting that space.
///
/// Also hides chats with no messages: a conversation only becomes real once it
/// holds one, and an abandoned starter (widget tap never sent) should not
/// linger between the sweep that deletes it and the next render.
enum ChatListFilter {
    /// Chats visible for the current space selection.
    ///
    /// With a space selected, shows that space's chats (private or not). With no
    /// selection, shows every chat except those in private spaces; chats with no
    /// space remain visible.
    static func visibleChats(
        _ chats: [Chat],
        spaces: [Space],
        selectedSpaceID: UUID?
    ) -> [Chat] {
        func isEligible(_ chat: Chat) -> Bool {
            !chat.messages.isEmpty
        }

        if let selectedSpaceID {
            return chats.filter { $0.spaceID == selectedSpaceID && isEligible($0) }
        }

        let privateSpaceIDs = Set(spaces.filter(\.isPrivate).map(\.id))
        return chats.filter { chat in
            guard isEligible(chat) else { return false }
            guard let spaceID = chat.spaceID else { return true }
            return !privateSpaceIDs.contains(spaceID)
        }
    }
}
