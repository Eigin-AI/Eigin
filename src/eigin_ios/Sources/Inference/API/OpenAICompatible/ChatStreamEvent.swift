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
    /// The stream has finished.
    case finished(FinishReason)

    enum FinishReason: String, Equatable {
        case stop
        case toolCalls = "tool_calls"
    }
}
