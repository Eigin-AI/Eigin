import Foundation
import SwiftData

/// Read-only transcript queries with chat ownership and response limits.
@MainActor
enum ChatTranscriptAccess {
    enum AccessError: Error, LocalizedError {
        case invalid(String)

        var errorDescription: String? {
            switch self {
            case .invalid(let message):
                message
            }
        }
    }

    static func execute(
        _ call: ToolCall,
        agent: Agent,
        spaceID: UUID?,
        currentChatID: UUID?,
        search: Bool
    ) -> ToolResult {
        do {
            guard let args = ToolHelpers.parseArguments(call.function.arguments) else {
                throw AccessError.invalid("Invalid JSON arguments")
            }
            guard let context = agent.modelContext else {
                throw AccessError.invalid("Transcript store is unavailable")
            }
            let chatID = try requestedChatID(args, currentChatID: currentChatID)
            guard let chat = ChatLookup.find(chatID, in: context),
                  chat.agentID == agent.id,
                  spaceID == nil || chat.spaceID == spaceID
            else {
                throw AccessError.invalid("Chat not found")
            }
            let query = try requestedQuery(args, chatID: chatID, search: search, context: context)
            return try execute(query, callID: call.id, chatID: chatID, context: context)
        } catch {
            return ToolResult(
                toolCallID: call.id,
                content: ToolHelpers.output(errors: [error.localizedDescription]),
                isError: true
            )
        }
    }

    private static func execute(
        _ query: Query, callID: String, chatID: UUID, context: ModelContext
    ) throws -> ToolResult {
        switch query {
        case .message(let message, let offset):
            return try readMessage(message, offset: offset, callID: callID)
        case .search(let text, let before, let limit):
            let found = try searchMessages(
                chatID: chatID, before: before, query: text, limit: limit, context: context
            )
            return boundedResult(callID) { budget in
                var result = searchResult(found.messages, query: text, budget: budget)
                if let cursor = found.cursor {
                    result["next_before_message_id"] = cursor.uuidString
                }
                return result
            }
        case .surrounding(let anchor, let limit):
            let older = try fetch(
                chatID: chatID, anchor: anchor, newer: false, limit: limit / 2, context: context
            )
            let newer = try fetch(
                chatID: chatID, anchor: anchor, newer: true,
                limit: max(0, limit - older.count - 1), context: context
            )
            let messages = older.reversed() + [anchor] + newer
            return boundedResult(callID) { budget in
                transcriptResult(messages, anchorID: anchor.id, budget: budget)
            }
        case .recent(let before, let limit):
            let messages = try fetch(
                chatID: chatID, anchor: before, newer: false, limit: limit, context: context
            )
            return boundedResult(callID) { budget in
                transcriptResult(messages.reversed(), anchorID: nil, budget: budget)
            }
        }
    }

    private static func readMessage(
        _ message: Message,
        offset: Int,
        callID: String
    ) throws -> ToolResult {
        let text = ChatTags.stripAll(from: message.content)
        guard offset <= text.count else {
            throw AccessError.invalid("content_offset exceeds message length")
        }
        return boundedResult(callID) { budget in
            let content = String(text.dropFirst(offset).prefix(budget))
            var result: [String: Any] = [
                "message_id": message.id.uuidString,
                "role": message.role,
                "content": content,
                "content_offset": offset,
            ]
            if offset + content.count < text.count {
                result["next_content_offset"] = offset + content.count
            }
            return result
        }
    }
}
