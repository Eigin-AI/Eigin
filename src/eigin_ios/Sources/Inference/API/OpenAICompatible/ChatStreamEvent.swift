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
