import Foundation

extension ChatTranscriptAccess {
    static func boundedResult(_ id: String, result: (Int) -> [String: Any]) -> ToolResult {
        var budget = 3000
        var content = ToolHelpers.output(result: result(budget))
        while content.utf8.count > 10000, budget > 1 {
            budget /= 2
            content = ToolHelpers.output(result: result(budget))
        }
        guard content.utf8.count <= 10000 else {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers
                    .output(
                        errors: [
                            "A transcript character exceeds the response byte limit. This excerpt cannot be returned.",
                        ]
                    ),
                isError: true
            )
        }
        return ToolResult(toolCallID: id, content: content, isError: false)
    }

    static func searchResult(
        _ messages: [Message],
        query: String,
        budget: Int
    ) -> [String: Any] {
        let hits: [[String: Any]] = messages.map { message in
            let text = ChatTags.stripAll(from: message.content)
            let match = literalMatch(query, in: text)
            let start = match.map { text.index(
                $0.lowerBound,
                offsetBy: -100,
                limitedBy: text.startIndex
            ) ?? text.startIndex } ?? text.startIndex
            return [
                "message_id": message.id.uuidString,
                "role": message.role,
                "timestamp": message.timestamp.ISO8601Format(),
                "excerpt": String(text[start...].prefix(min(
                    240,
                    max(1, budget / max(1, messages.count))
                ))),
            ]
        }
        var result: [String: Any] = ["hits": hits]
        if let first = messages.first { result["next_before_message_id"] = first.id.uuidString }
        return result
    }

    static func transcriptResult(
        _ messages: [Message],
        anchorID: UUID?,
        budget: Int
    ) -> [String: Any] {
        var remaining = budget
        var selected: [UUID: (String, Int, Bool)] = [:]
        // Reserve text for the requested anchor before spending the budget on neighbours.
        var priority = Array(messages.reversed())
        if let anchorID, let index = priority.firstIndex(where: { $0.id == anchorID }) {
            let anchor = priority.remove(at: index)
            priority.insert(anchor, at: 0)
        }
        for message in priority {
            let text = ChatTags.stripAll(from: message.content)
            let excerpt = String(text.suffix(remaining))
            guard remaining > 0 || text.isEmpty else { continue }
            selected[message.id] = (excerpt, text.count - excerpt.count, excerpt.count < text.count)
            remaining -= excerpt.count
        }
        var entries: [[String: Any]] = []
        var lines: [String] = []
        for message in messages {
            guard let (text, offset, truncated) = selected[message.id] else { continue }
            entries.append([
                "message_id": message.id.uuidString,
                "role": message.role,
                "timestamp": message.timestamp.ISO8601Format(),
                "content": text,
                "content_offset": offset,
                "truncated": truncated,
            ])
            lines.append("\(message.role == "user" ? "User" : "Assistant"): \(text)")
        }
        var result: [String: Any] = [
            "messages": entries,
            "transcript": lines.joined(separator: "\n\n"),
            "truncated": selected.count < messages.count || selected.values.contains { $0.2 },
            "recovery": "Use read_message_id with content_offset to read any message from its beginning or continue a long message.",
        ]
        if let first = entries.first?["message_id"] { result["next_before_message_id"] = first }
        return result
    }
}
