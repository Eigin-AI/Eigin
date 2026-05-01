import Foundation
import SwiftData

/// Moves a chat to a different space and migrates associated knowledge entries.
///
/// Both the UI (`ChatViewModel.moveToSpace`) and the tool (`MoveChatToSpaceTool`)
/// go through this to ensure all related data follows the chat.
enum ChatMigration {
    /// Move a chat to a new space, migrating associated knowledge entries.
    /// Pass `nil` for `toSpaceID` to remove from a space (move to global).
    @MainActor
    static func moveChat(_ chat: Chat, toSpaceID: UUID?, context: ModelContext) {
        let chatID = chat.id

        // 1. Update the chat itself.
        chat.spaceID = toSpaceID
        chat.updatedAt = .now

        // 2. Migrate knowledge entries (FirmSource) created in this chat.
        let knowledgeDescriptor = FetchDescriptor<FirmSource>(
            predicate: #Predicate { $0.chatID == chatID }
        )
        if let sources = try? context.fetch(knowledgeDescriptor) {
            for source in sources {
                source.spaceID = toSpaceID
            }
        }
    }
}
