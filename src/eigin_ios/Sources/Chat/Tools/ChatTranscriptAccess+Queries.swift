import Foundation
import SwiftData

extension ChatTranscriptAccess {
    static func anchor(
        _ raw: Any?,
        chatID: UUID,
        context: ModelContext
    ) throws -> Message? {
        guard let raw else { return nil }
        guard let text = raw as? String,
              let id = UUID(uuidString: text)
        else { throw AccessError.invalid("Invalid message cursor") }
        var descriptor =
            FetchDescriptor<Message>(predicate: #Predicate {
                $0.id == id && $0.chat?
                    .id == chatID && ($0.role == "user" || $0.role == "assistant")
            })
        descriptor.fetchLimit = 1
        guard let message = try context.fetch(descriptor).first
        else { throw AccessError.invalid("Message cursor not found in chat") }
        return message
    }

    static func fetch(
        chatID: UUID,
        anchor: Message?,
        newer: Bool,
        limit: Int,
        context: ModelContext
    ) throws -> [Message] {
        guard limit > 0 else { return [] }
        let timestamp = anchor?.timestamp ?? (newer ? Date.distantPast : Date.distantFuture)
        let anchorID = anchor?.id ?? UUID()
        let hasAnchor = anchor != nil
        let scope = #Predicate<Message> { message in
            message.chat?.id == chatID && (message.role == "user" || message.role == "assistant")
        }
        let boundary: Predicate<Message>
        if !hasAnchor {
            boundary = #Predicate<Message> { _ in true }
        } else if newer {
            boundary = #Predicate<Message> { message in
                message
                    .timestamp > timestamp ||
                    (message.timestamp == timestamp && message.id > anchorID)
            }
        } else {
            boundary = #Predicate<Message> { message in
                message
                    .timestamp < timestamp ||
                    (message.timestamp == timestamp && message.id < anchorID)
            }
        }
        let predicate = #Predicate<Message> { scope.evaluate($0) && boundary.evaluate($0) }
        var descriptor = FetchDescriptor<Message>(
            predicate: predicate,
            sortBy: [
                SortDescriptor(
                    \.timestamp,
                    order: newer ? .forward : .reverse
                ),
                SortDescriptor(
                    \.id,
                    order: newer ? .forward : .reverse
                ),
            ]
        )
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor)
    }
}
