import EiginSDK
import Foundation

/// Maps request-local SDK conversation values without resolving attachment bytes.
enum MessagePreparationSDKConversion {
    typealias SDK = EiginSDK.Experimental.Conversation

    static func select(_ history: [ChatMessage]) throws -> SDK.Selection {
        try SDK.select(history.map(message))
    }

    static func prepare(
        _ selected: SDK.Selection, history: [ChatMessage],
        systemPrompt: String, systemHint: String?, supportsVision: Bool
    ) -> [ChatMessage] {
        SDK.prepare(selected, options: .init(
            systemPrompt: systemPrompt, systemHint: systemHint, supportsVision: supportsVision
        )).map { restore($0, history: history) }
    }

    static func conversation(_ selected: SDK.Selection, history: [ChatMessage]) -> [ChatMessage] {
        selected.messages.map { value in
            guard let index = value.sourceIndex
            else { preconditionFailure("Missing history provenance") }
            return restore(
                .init(origin: .history(sourceIndex: index), message: value),
                history: history
            )
        }
    }

    static func appendHint(_ hint: String, to messages: [ChatMessage]) -> [ChatMessage] {
        let values = messages.enumerated().map { index, value in
            SDK.PreparedMessage(
                origin: .history(sourceIndex: UInt64(index)),
                message: message(value)
            )
        }
        return SDK.appendHint(hint, to: values).map { restore($0, history: messages) }
    }

    static func message(_ message: ChatMessage) -> SDK.Message {
        .init(
            sourceIndex: nil, role: message.role, content: message.content, name: message.name,
            toolCallId: message.toolCallID,
            toolCalls: message.toolCalls?.map { .init(
                id: $0.id, kind: $0.type, name: $0.function.name, arguments: $0.function.arguments
            ) },
            attachments: message.attachments?.map { .init(
                id: $0.id.uuidString, kind: $0.kind.rawValue, mimeType: $0.mimeType,
                width: $0.width.map(Int64.init), height: $0.height.map(Int64.init),
                byteCount: Int64($0.byteCount)
            ) },
            providerMetadata: message.providerMetadata,
            reasoningHistory: message.reasoningHistory.map { .init(
                origin: InferenceSDKConversion.origin($0.origin), format: $0.format,
                payload: $0.payload, visibleText: $0.visibleText,
                additionalInputTokens: Int64($0.additionalInputTokens)
            ) },
            isCompactionSummary: message.isCompactionSummary,
            compactionRetainedMessageCount: message.compactionRetainedMessageCount.map(Int64.init)
        )
    }

    private static func restore(
        _ entry: SDK.PreparedMessage,
        history: [ChatMessage]
    ) -> ChatMessage {
        var result: ChatMessage
        switch entry.origin {
        case .history(let sourceIndex):
            guard let index = Int(exactly: sourceIndex), history.indices.contains(index) else {
                preconditionFailure("Invalid SDK history provenance")
            }
            result = history[index]
        case .summary:
            result = ChatMessage(role: "user", content: "", localID: "context-summary")
        case .summaryAcknowledgement:
            result = ChatMessage(role: "assistant", content: "", localID: "context-summary-ack")
        case .system, .hintFallback, .supplied:
            result = ChatMessage(role: entry.message.role, content: "")
        }
        let value = entry.message
        result.role = value.role
        result.content = value.content
        result.name = value.name
        result.toolCallID = value.toolCallId
        result.toolCalls = value.toolCalls?.map { .init(
            id: $0.id, type: $0.kind, function: .init(name: $0.name, arguments: $0.arguments)
        ) }
        result.attachments = value.attachments?.map { attachment in
            guard let id = UUID(uuidString: attachment.id),
                  let kind = AttachmentKind(rawValue: attachment.kind)
            else {
                preconditionFailure("SDK changed an opaque attachment reference")
            }
            return .init(
                id: id,
                kind: kind,
                mimeType: attachment.mimeType,
                width: attachment.width.map { Int($0) },
                height: attachment.height.map { Int($0) },
                byteCount: Int(attachment.byteCount)
            )
        }
        result.providerMetadata = value.providerMetadata
        result.reasoningHistory = value.reasoningHistory.map { reasoning in
            guard let providerID = UUID(uuidString: reasoning.origin.providerId) else {
                preconditionFailure("SDK changed reasoning origin")
            }
            return .init(
                origin: .init(
                    providerID: providerID,
                    endpoint: reasoning.origin.endpoint,
                    model: reasoning.origin.model
                ),
                format: reasoning.format,
                payload: reasoning.payload,
                visibleText: reasoning.visibleText,
                additionalInputTokens: Int(reasoning.additionalInputTokens)
            )
        }
        result.isCompactionSummary = value.isCompactionSummary
        result.compactionRetainedMessageCount = value.compactionRetainedMessageCount.map { Int($0) }
        return result
    }
}
