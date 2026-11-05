import Foundation
import SwiftData

/// Schema V12 adds private continuation state to messages.
extension SchemaV12 {
    @Model
    final class Message {
        var id: UUID
        var role: String
        var content: String
        var toolCallID: String?
        var toolCallsData: Data?
        var timestamp: Date

        /// Compaction boundary: this message replaces the older conversation.
        var isCompactionSummary: Bool = false

        /// For `isCompactionSummary` messages: how many rows immediately before
        /// it are kept verbatim. `nil` (→ 0) for non-summaries and summaries
        /// created before retention shipped.
        var compactionRetainedMessageCount: Int?

        /// JSON-encoded ``[MessageAttachment]`` references.
        var attachmentsData: Data?

        /// Encoded private continuation state, deleted with its message.
        var reasoningHistoryData: Data?

        var chat: Chat?

        init(
            role: String,
            content: String,
            toolCallID: String? = nil,
            toolCallsData: Data? = nil,
            attachmentsData: Data? = nil
        ) {
            id = UUID()
            self.role = role
            self.content = content
            self.toolCallID = toolCallID
            self.toolCallsData = toolCallsData
            self.attachmentsData = attachmentsData
            compactionRetainedMessageCount = nil
            timestamp = .now
        }

        // MARK: - Conversion

        /// Decodes persisted tool calls from JSON data.
        var toolCalls: [ToolCall]? {
            guard let data = toolCallsData else { return nil }
            return try? JSONDecoder().decode([ToolCall].self, from: data)
        }

        /// Decodes persisted attachment references from JSON data.
        var attachments: [MessageAttachment]? {
            guard let data = attachmentsData else { return nil }
            return try? JSONDecoder().decode([MessageAttachment].self, from: data)
        }

        /// Converts this persisted Message to a transient ChatMessage for API use.
        func toChatMessage() -> ChatMessage {
            let contentValue: String? = content.isEmpty && toolCallsData != nil ? nil : content
            var msg = ChatMessage(
                role: role,
                content: contentValue,
                toolCallID: toolCallID,
                toolCalls: toolCalls,
                attachments: attachments,
                localID: id.uuidString
            )
            if let data = reasoningHistoryData {
                msg.reasoningHistory = ProviderAdapterFactory.decodeReasoningHistory(data)
            }
            msg.isCompactionSummary = isCompactionSummary
            msg.compactionRetainedMessageCount = compactionRetainedMessageCount
            return msg
        }

        /// Creates a persisted Message from a transient ChatMessage.
        static func from(_ chatMessage: ChatMessage) -> Message {
            let toolCallsData: Data? = if let toolCalls = chatMessage.toolCalls {
                try? JSONEncoder().encode(toolCalls)
            } else {
                nil
            }

            let attachmentsData: Data? = if let attachments = chatMessage.attachments {
                try? JSONEncoder().encode(attachments)
            } else {
                nil
            }

            let message = Message(
                role: chatMessage.role,
                content: chatMessage.content ?? "",
                toolCallID: chatMessage.toolCallID,
                toolCallsData: toolCallsData,
                attachmentsData: attachmentsData
            )
            message.reasoningHistoryData = chatMessage.reasoningHistory.flatMap {
                try? JSONEncoder().encode($0)
            }
            message.isCompactionSummary = chatMessage.isCompactionSummary
            message.compactionRetainedMessageCount = chatMessage.compactionRetainedMessageCount
            return message
        }
    }
}
