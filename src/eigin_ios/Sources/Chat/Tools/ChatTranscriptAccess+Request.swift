import CoreFoundation
import Foundation
import SwiftData

extension ChatTranscriptAccess {
    enum Query {
        case message(Message, offset: Int)
        case search(String, before: Message?, limit: Int)
        case surrounding(Message, limit: Int)
        case recent(before: Message?, limit: Int)
    }

    static func requestedChatID(_ args: [String: Any], currentChatID: UUID?) throws -> UUID {
        if let value = args["chat_id"] {
            guard let text = value as? String, let id = UUID(uuidString: text) else {
                throw AccessError.invalid("Invalid chat_id")
            }
            return id
        }
        guard let currentChatID else {
            throw AccessError.invalid("chat_id is required outside a chat")
        }
        return currentChatID
    }

    static func requestedQuery(
        _ args: [String: Any], chatID: UUID, search: Bool, context: ModelContext
    ) throws -> Query {
        let limit = try integer(args, key: "limit", defaultValue: 10, maximum: 20)
        let before = try anchor(args["before_message_id"], chatID: chatID, context: context)
        let around = try anchor(args["around_message_id"], chatID: chatID, context: context)
        let read = try anchor(args["read_message_id"], chatID: chatID, context: context)
        guard before == nil || around == nil else {
            throw AccessError.invalid("Choose before_message_id or around_message_id")
        }
        guard read == nil || (before == nil && around == nil && !search) else {
            throw AccessError.invalid("read_message_id cannot be combined with ranges or search")
        }
        if args["content_offset"] != nil, read == nil {
            throw AccessError.invalid("content_offset requires read_message_id")
        }
        let offset = try integer(
            args, key: "content_offset", defaultValue: 0, maximum: Int.max, minimum: 0
        )
        if let read {
            return .message(read, offset: offset)
        }
        if search {
            let text = try searchText(args, around: around)
            return .search(text, before: before, limit: limit)
        }
        if let around {
            return .surrounding(around, limit: limit)
        }
        return .recent(before: before, limit: limit)
    }

    private static func searchText(_ args: [String: Any], around: Message?) throws -> String {
        guard let text = args["query"] as? String,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              text.count <= 500, around == nil
        else {
            throw AccessError.invalid(
                "Search requires a nonempty query of at most 500 characters and no around_message_id"
            )
        }
        return text
    }

    private static func integer(
        _ args: [String: Any], key: String, defaultValue: Int, maximum: Int, minimum: Int = 1
    ) throws -> Int {
        guard let raw = args[key] else {
            return defaultValue
        }
        guard let number = raw as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite,
              number.doubleValue.rounded(.towardZero) == number.doubleValue,
              number.doubleValue >= Double(minimum),
              number.doubleValue < Double(Int.max)
        else {
            throw AccessError.invalid("Invalid \(key)")
        }
        return min(number.intValue, maximum)
    }
}
