import Foundation

/// Rough token-count estimator using character-based heuristics.
///
/// Intentionally conservative (overestimates slightly) so compaction triggers
/// before hitting the actual context limit. Not a tokeniser — accuracy within ~20 %
/// is sufficient for deciding when to compact.
enum TokenEstimator {
    /// Estimates token count for a single string.
    static func estimate(_ text: String) -> Int {
        // ~4 characters per token on average for English + JSON
        max(1, text.count / 4)
    }

    /// Estimates token count for a message array including per-message framing overhead.
    static func estimate(messages: [ChatMessage]) -> Int {
        var total = 0
        for message in messages {
            total += 4 // role, framing, separators
            total += estimate(message.content ?? "")
            if let toolCalls = message.toolCalls {
                for call in toolCalls {
                    total += 10 // function call framing
                    total += estimate(call.function.name)
                    total += estimate(call.function.arguments)
                }
            }
            if let name = message.name {
                total += estimate(name)
            }
        }
        return total
    }

    /// Estimates token count for tool definitions.
    static func estimate(toolDefinitions: [ToolDefinition]) -> Int {
        // Each tool definition is ~100-200 tokens of JSON Schema.
        toolDefinitions.count * 150
    }

    /// Estimates total request size (messages + tool definitions).
    static func estimateRequest(
        messages: [ChatMessage],
        toolDefinitions: [ToolDefinition]?
    ) -> Int {
        var total = estimate(messages: messages)
        if let tools = toolDefinitions {
            total += estimate(toolDefinitions: tools)
        }
        return total
    }
}
