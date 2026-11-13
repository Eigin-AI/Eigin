import Foundation

/// Repairs unambiguous duplicate results within a single tool-call round.
enum ToolResultRepair {
    static func repair(_ messages: ArraySlice<ChatMessage>, calls: [ToolCall]) -> [ChatMessage] {
        guard Set(calls.map(\.id)).count == calls.count else { return Array(messages) }
        var unique: [ChatMessage] = []
        for message in messages where !unique.contains(where: { samePayload($0, message) }) {
            unique.append(message)
        }
        let groups = Dictionary(grouping: unique, by: \.toolCallID)
        return unique.filter { message in
            guard let call = calls.first(where: { $0.id == message.toolCallID }),
                  isInterruptedPlaceholder(message, call: call) else { return true }
            let realResults = groups[message.toolCallID, default: []].filter {
                !isInterruptedPlaceholder($0, call: call)
            }
            return realResults.count != 1
        }
    }

    private static func samePayload(_ lhs: ChatMessage, _ rhs: ChatMessage) -> Bool {
        lhs.toolCallID != nil && lhs.toolCallID == rhs.toolCallID && lhs.content == rhs.content
            && lhs.name == rhs.name && lhs.toolCalls == rhs.toolCalls
            && lhs.attachments == rhs.attachments && lhs.providerMetadata == rhs.providerMetadata
            && lhs.reasoningHistory == rhs.reasoningHistory
            && lhs.isCompactionSummary == rhs.isCompactionSummary
            && lhs.compactionRetainedMessageCount == rhs.compactionRetainedMessageCount
    }

    private static func isInterruptedPlaceholder(_ message: ChatMessage, call: ToolCall) -> Bool {
        message.content == ToolResult.interruptedContent
            && (message.name == nil || message.name == call.function.name)
            && (message.attachments ?? []).isEmpty
            && (message.toolCalls ?? []).isEmpty
            && (message.providerMetadata ?? [:]).isEmpty
            && message.reasoningHistory == nil
            && !message.isCompactionSummary
            && message.compactionRetainedMessageCount == nil
    }
}
