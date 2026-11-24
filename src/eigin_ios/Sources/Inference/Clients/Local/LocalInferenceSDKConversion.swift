import EiginSDK
import Foundation

/// Preserves Gemma's text/tool history without applying cloud-only validation or attachment
/// loading.
enum LocalInferenceSDKConversion {
    typealias SDK = EiginSDK.Experimental.Inference

    static func input(
        messages: [ChatMessage],
        model: String,
        tools: [ToolDefinition]?
    ) throws -> SDK.Input {
        try .init(
            model: model,
            messages: messages.map {
                .init(
                    role: $0.role,
                    content: $0.content,
                    name: $0.name,
                    toolCallId: $0.toolCallID,
                    toolCalls: $0.toolCalls?.map(call),
                    images: [],
                    hasAttachments: false,
                    providerMetadata: [:],
                    reasoningHistory: nil
                )
            },
            tools: tools?.map(InferenceSDKConversion.tool), reasoningEffort: nil,
            promptCacheKey: nil, modelFamily: .google, isRelay: false, reasoningOrigin: nil,
            textOnly: false
        )
    }

    static func call(_ value: ToolCall) -> SDK.ToolCall {
        .init(
            id: value.id,
            kind: value.type,
            name: value.function.name,
            arguments: value.function.arguments
        )
    }

    static func call(_ value: SDK.ToolCall) -> ToolCall {
        .init(
            id: value.id,
            type: value.kind,
            function: .init(name: value.name, arguments: value.arguments)
        )
    }

    static func failure(_ error: any Error) -> any Error {
        guard case SDK.Failure.LocalUnavailable(let code, let reason) = error else { return error }
        switch code {
        case "not_downloaded": return LocalClientError.modelNotDownloaded
        case "not_loaded": return LocalClientError.modelNotLoaded
        case "device_unsupported": return LocalClientError.deviceUnsupported(detail: reason)
        case "unsupported_model": return LocalClientError.unsupportedModel
        default: return error
        }
    }
}
