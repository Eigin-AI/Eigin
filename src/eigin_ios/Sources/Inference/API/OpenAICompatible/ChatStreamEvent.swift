import Foundation

/// Events emitted by the structured chat completion event stream.
enum ChatStreamEvent: Equatable {
    /// A fragment of the assistant's text content.
    case contentDelta(String)
    /// A fully assembled tool call (emitted when finish_reason is tool_calls).
    case toolCall(ToolCall)
    /// Provider-specific metadata (e.g. Gemini thought_signature) to attach to the assistant
    /// message.
    case providerMetadata([String: String])
    /// Completed private continuation state, emitted only after a successful finish reason.
    case reasoningHistory(ReasoningHistory)
    /// Client-observed useful-output measurements from the inference transport.
    case performance(InferencePerformance)
    /// The stream has finished.
    case finished(FinishReason)

    enum FinishReason: String, Equatable {
        case stop
        case toolCalls = "tool_calls"
    }
}

/// Uses the same useful-output boundaries and token accounting as relay observations.
struct InferencePerformance: Equatable {
    let timeToFirstToken: Duration?
    let tokensPerSecond: Double?
}

extension ChatStreamEvent {
    /// Only output that can advance the turn settles a model race.
    var isUsefulOutput: Bool {
        switch self {
        case .contentDelta(let text): !text.isEmpty
        case .toolCall(let call):
            !call.id.isEmpty && !call.function.name.isEmpty
                && ToolHelpers.parseArguments(call.function.arguments) != nil
        default: false
        }
    }

    /// Estimated memory held while waiting for a candidate's first answer or usable tool call.
    var bufferedByteCount: Int {
        switch self {
        case .contentDelta(let text): text.utf8.count + 64
        case .toolCall(let call):
            call.id.utf8.count + call.function.name.utf8.count + call.function.arguments.utf8
                .count + 64
        case .providerMetadata(let values):
            values.reduce(64) { $0 + $1.key.utf8.count + $1.value.utf8.count + 64 }
        case .reasoningHistory(let history):
            history.payload.count + history.visibleText.utf8.count + history.format.utf8.count
                + history.origin.endpoint.utf8.count + history.origin.model.utf8.count + 128
        case .performance, .finished: 64
        }
    }
}
