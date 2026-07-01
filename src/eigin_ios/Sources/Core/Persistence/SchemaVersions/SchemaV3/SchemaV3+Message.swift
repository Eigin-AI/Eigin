import Foundation
import SwiftData

/// Unchanged since V1, but re-declared here because its `chat` relationship
/// must resolve to ``SchemaV3/Chat``, not ``SchemaV1/Chat``.
extension SchemaV3 {
    @Model
    final class Message {
        var id: UUID
        var role: String
        var content: String
        var toolCallID: String?
        var toolCallsData: Data?
        var isCompactionSummary: Bool = false
        var timestamp: Date

        var chat: Chat?

        init(role: String, content: String, toolCallID: String? = nil, toolCallsData: Data? = nil) {
            id = UUID()
            self.role = role
            self.content = content
            self.toolCallID = toolCallID
            self.toolCallsData = toolCallsData
            timestamp = .now
        }

        // MARK: - Conversion

        /// Decodes persisted tool calls from JSON data.
        var toolCalls: [ToolCall]? {
            guard let data = toolCallsData else { return nil }
            return try? JSONDecoder().decode([ToolCall].self, from: data)
        }

        /// Converts this persisted Message to a transient ChatMessage for API use.
        func toChatMessage() -> ChatMessage {
            let contentValue: String? = content.isEmpty && toolCallsData != nil ? nil : content
            var msg = ChatMessage(
                role: role,
                content: contentValue,
                toolCallID: toolCallID,
                toolCalls: toolCalls,
                localID: id.uuidString
            )
            msg.isCompactionSummary = isCompactionSummary
            return msg
        }

        /// Creates a persisted Message from a transient ChatMessage.
        static func from(_ chatMessage: ChatMessage) -> Message {
            let toolCallsData: Data? = if let toolCalls = chatMessage.toolCalls {
                try? JSONEncoder().encode(toolCalls)
            } else {
                nil
            }

            let message = Message(
                role: chatMessage.role,
                content: chatMessage.content ?? "",
                toolCallID: chatMessage.toolCallID,
                toolCallsData: toolCallsData
            )
            message.isCompactionSummary = chatMessage.isCompactionSummary
            return message
        }
    }
}
