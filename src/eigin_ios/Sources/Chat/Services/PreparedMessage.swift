import Foundation

/// Encoded message values ready for insertion into the caller's persistence context.
struct PreparedMessage: Sendable {
    private let source: ChatMessage
    private let toolCallsData: Data?
    private let attachmentsData: Data?
    private let reasoningHistoryData: Data?

    init(_ message: ChatMessage) {
        source = message
        let encoder = JSONEncoder()
        toolCallsData = message.toolCalls.flatMap { try? encoder.encode($0) }
        attachmentsData = message.attachments.flatMap { try? encoder.encode($0) }
        reasoningHistoryData = message.reasoningHistory.flatMap { try? encoder.encode($0) }
    }

    /// Encodes turn output away from the main actor without moving SwiftData models.
    @concurrent
    static func prepare(_ messages: [ChatMessage]) async -> [PreparedMessage] {
        messages.map(PreparedMessage.init)
    }

    /// Creates an uninserted model on the caller's executor.
    func makeMessage() -> Message {
        let message = Message(
            role: source.role,
            content: source.content ?? "",
            toolCallID: source.toolCallID,
            toolCallsData: toolCallsData,
            attachmentsData: attachmentsData
        )
        // Streaming IDs carry a display prefix; persisted IDs keep their UUID identity.
        let identity = source.localID.hasPrefix("msg-")
            ? String(source.localID.dropFirst(4)) : source.localID
        if let id = UUID(uuidString: identity) { message.id = id }
        message.reasoningHistoryData = reasoningHistoryData
        message.isCompactionSummary = source.isCompactionSummary
        message.compactionRetainedMessageCount = source.compactionRetainedMessageCount
        return message
    }
}
