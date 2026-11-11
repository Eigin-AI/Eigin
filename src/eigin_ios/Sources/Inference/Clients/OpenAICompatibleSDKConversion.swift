import EiginSDK
import Foundation

/// Maps app-owned messages and metadata onto value-based SDK inputs.
enum OpenAICompatibleSDKConversion {
    private typealias SDK = EiginSDK.Experimental.Inference

    static func message(_ message: ChatMessage, store: any ChatAttachmentStoring) -> EiginSDK
        .Experimental.Inference.Message
    {
        let images = (message.attachments ?? []).filter { $0.kind == .image }
            .compactMap { attachment -> SDK.Image? in
                guard let data = store.load(id: attachment.id) else { return nil }
                return .init(mimeType: attachment.mimeType, bytes: data)
            }
        return .init(
            role: message.role, content: message.content, name: message.name,
            toolCallId: message.toolCallID,
            toolCalls: message.toolCalls?.map { .init(
                id: $0.id,
                kind: $0.type,
                name: $0.function.name,
                arguments: $0.function.arguments
            ) },
            images: images, hasAttachments: message.attachments?.isEmpty == false,
            providerMetadata: message.providerMetadata ?? [:],
            reasoningHistory: message.reasoningHistory.map {
                .init(
                    origin: origin($0.origin),
                    format: $0.format,
                    payload: $0.payload,
                    visibleText: $0.visibleText,
                    additionalInputTokens: Int64($0.additionalInputTokens)
                )
            }
        )
    }

    static func tool(_ tool: ToolDefinition) throws -> EiginSDK.Experimental.Inference
        .ToolDefinition
    {
        try .init(
            name: tool.function.name,
            description: tool.function.description,
            parametersJson: String(
                decoding: JSONEncoder().encode(tool.function.parameters),
                as: UTF8.self
            )
        )
    }

    static func origin(_ origin: ReasoningOrigin) -> EiginSDK.Experimental.Inference
        .ReasoningOrigin
    {
        .init(
            providerId: origin.providerID.uuidString,
            endpoint: origin.endpoint,
            model: origin.model
        )
    }

    static func family(_ family: ModelFamily?) -> EiginSDK.Experimental.Inference.ModelFamily? {
        switch family {
        case .google: .google
        case .mistral: .mistral
        case .anthropic: .anthropic
        case nil: nil
        default: .other
        }
    }

    static func event(_ event: EiginSDK.Experimental.Inference.Event) throws -> ChatStreamEvent {
        switch event {
        case .contentDelta(let text): return .contentDelta(text)
        case .toolCall(let call):
            return .toolCall(.init(
                id: call.id,
                type: call.kind,
                function: .init(name: call.name, arguments: call.arguments)
            ))
        case .providerMetadata(let values): return .providerMetadata(values)
        case .reasoningHistory(let history):
            guard let providerID = UUID(uuidString: history.origin.providerId)
            else { throw OpenAICompatibleClientError.invalidResponse }
            return .reasoningHistory(.init(
                origin: .init(
                    providerID: providerID,
                    endpoint: history.origin.endpoint,
                    model: history.origin.model
                ),
                format: history.format, payload: history.payload, visibleText: history.visibleText,
                additionalInputTokens: Int(clamping: history.additionalInputTokens)
            ))
        case .finished(let reason): return .finished(reason == .toolCalls ? .toolCalls : .stop)
        }
    }

    static func error(_ error: any Error) -> any Error {
        guard let failure = error as? SDK.Failure else { return error }
        switch failure {
        case .InvalidUrl(let url): return OpenAICompatibleClientError.invalidURL(url)
        case .Http(let status, let body): return OpenAICompatibleClientError.httpError(
                Int(status),
                body: body
            )
        case .Interrupted, .LimitExceeded: return StreamCompletionError.interrupted
        case .OutputLimit: return StreamCompletionError.outputLimit
        case .PolicyStop: return StreamCompletionError.policyStop
        case .Cancelled: return CancellationError()
        case .Transport(let reason, _, _):
            return URLError(.unknown, userInfo: [NSLocalizedDescriptionKey: reason])
        case .InvalidData, .Busy: return OpenAICompatibleClientError.invalidResponse
        }
    }
}
