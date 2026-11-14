import Foundation
import SwiftData

extension ChatTranscriptAccess {
    /// Matches literal text using one locale for both membership and excerpts.
    static func literalMatch(_ query: String, in text: String) -> Range<String.Index>? {
        text.range(
            of: query,
            options: [.caseInsensitive, .literal],
            locale: Locale(identifier: "en_US_POSIX")
        )
    }

    /// Bounds each scan and exposes progress even when no message matches.
    static func searchMessages(
        chatID: UUID,
        before: Message?,
        query: String,
        limit: Int,
        context: ModelContext
    ) throws -> (messages: [Message], cursor: UUID?) {
        var cursor = before
        var matches: [Message] = []
        var scanned = 0
        while scanned < 1000 {
            let batch = try fetch(
                chatID: chatID,
                anchor: cursor,
                newer: false,
                limit: 100,
                context: context
            )
            guard !batch.isEmpty else { return (matches.reversed(), nil) }
            for message in batch {
                cursor = message
                scanned += 1
                if literalMatch(query, in: ChatTags.stripAll(from: message.content)) != nil {
                    matches.append(message)
                    if matches.count == limit { return (matches.reversed(), cursor?.id) }
                }
            }
            if batch.count < 100 { return (matches.reversed(), nil) }
        }
        return (matches.reversed(), cursor?.id)
    }
}
