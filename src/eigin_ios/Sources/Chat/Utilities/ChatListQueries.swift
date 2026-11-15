import Foundation
import SwiftData

/// Store-side selection keeps list entry independent of transcript materialization.
enum ChatListQueries {
    /// Chats containing any message, including system and tool messages.
    static var populatedChats: FetchDescriptor<Chat> {
        FetchDescriptor(
            predicate: #Predicate<Chat> { !$0.messages.isEmpty },
            sortBy: [SortDescriptor(\Chat.updatedAt, order: .reverse)]
        )
    }

    /// Empty conversations eligible for orphan cleanup after claim checks.
    static var emptyChats: FetchDescriptor<Chat> {
        FetchDescriptor(predicate: #Predicate<Chat> { $0.messages.isEmpty })
    }

    /// Only the newest nonempty user or assistant message is needed for a row.
    static func preview(chat: Chat) -> FetchDescriptor<Message> {
        let chatID = chat.persistentModelID
        var descriptor = FetchDescriptor<Message>(
            predicate: #Predicate<Message> {
                $0.chat?.persistentModelID == chatID &&
                    ($0.role == "user" || $0.role == "assistant") && $0.content != ""
            },
            sortBy: [SortDescriptor(\Message.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return descriptor
    }
}
