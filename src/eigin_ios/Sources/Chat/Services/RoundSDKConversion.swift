import EiginSDK
import Foundation

/// Maps app stream and execution values to the SDK-owned round.
enum RoundSDKConversion {
    typealias SDK = EiginSDK.Experimental.Agent

    static func event(_ event: ChatStreamEvent) -> EiginSDK.Experimental.Inference.Event {
        switch event {
        case .contentDelta(let text): .contentDelta(text: text)
        case .toolCall(let value): .toolCall(call: call(value))
        case .providerMetadata(let values): .providerMetadata(values: values)
        case .reasoningHistory(let history): .reasoningHistory(history: .init(
                origin: InferenceSDKConversion.origin(history.origin), format: history.format,
                payload: history.payload, visibleText: history.visibleText,
                additionalInputTokens: Int64(history.additionalInputTokens)
            ))
        case .performance(let value): .performance(measurement: .init(
                timeToFirstTokenMs: value.timeToFirstToken
                    .map {
                        Double($0.components.seconds) * 1000 + Double($0.components.attoseconds) /
                            1e15
                    },
                tokensPerSecond: value.tokensPerSecond
            ))
        case .finished(let reason): .finished(reason: reason == .toolCalls ? .toolCalls : .stop)
        }
    }

    static func call(_ value: ToolCall) -> EiginSDK.Experimental.Inference.ToolCall {
        .init(
            id: value.id,
            kind: value.type,
            name: value.function.name,
            arguments: value.function.arguments
        )
    }

    static func call(_ value: EiginSDK.Experimental.Inference.ToolCall) -> ToolCall {
        .init(
            id: value.id,
            type: value.kind,
            function: .init(name: value.name, arguments: value.arguments)
        )
    }

    static func result(_ value: ToolResult) -> SDK.ToolResult {
        .init(toolCallId: value.toolCallID, content: value.content)
    }

    static func message(
        _ value: EiginSDK.Experimental.Conversation.Message,
        localID: String? = nil
    ) -> ChatMessage {
        MessagePreparationSDKConversion.restore(
            .init(origin: .supplied, message: value),
            history: [],
            localID: localID
        )
    }

    static func finish(_ round: SDK.Round) throws -> SDK.Outcome {
        do {
            return try round.finishStream()
        } catch SDK.Failure.Interrupted {
            throw StreamCompletionError.interrupted
        } catch SDK.Failure.InvalidToolCall {
            throw StreamCompletionError.invalidToolCall
        }
    }
}
