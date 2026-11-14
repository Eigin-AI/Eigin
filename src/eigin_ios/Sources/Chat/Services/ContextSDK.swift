import EiginSDK

/// Converts app messages at the experimental SDK context boundary.
enum ContextSDK {
    typealias Context = EiginSDK.Experimental.Context

    static func messages(_ messages: [ChatMessage], model: String? = nil) -> [Context.Message] {
        messages.map { message in
            let reasoningTokens: Int = if let history = message.reasoningHistory,
                                          history.matches(message, origin: history.origin)
            {
                history.additionalInputTokens
            } else {
                0
            }
            let inputTokens = (message.attachments ?? [])
                .reduce(reasoningTokens) { total, attachment in
                    let image = KnownModelCatalog.imageInputBudget(
                        width: attachment.width,
                        height: attachment.height,
                        model: model
                    )
                    let (sum, overflow) = total.addingReportingOverflow(image)
                    return overflow ? Int.max : sum
                }
            return Context.Message(
                role: message.role,
                content: message.content,
                name: message.name,
                toolCalls: (message.toolCalls ?? []).map {
                    Context.ToolCall(name: $0.function.name, arguments: $0.function.arguments)
                },
                additionalInputTokens: Int64(inputTokens),
                hasReasoningHistory: message.reasoningHistory != nil
            )
        }
    }

    static func apply(_ selection: Context.Selection, to messages: [ChatMessage]) -> [ChatMessage] {
        var result = Array(messages.dropFirst(selection.startIndex))
        if let content = selection.partialContent, let first = result.first {
            // Rebuild partial messages with fresh identity and cleared local/provider metadata.
            result[0] = ChatMessage(
                role: first.role, content: content, toolCallID: first.toolCallID,
                name: first.name, toolCalls: first.toolCalls
            )
        }
        return result
    }
}
