import EiginSDK
import Foundation

/// Rough token estimates delegated to the SDK's grapheme-based heuristic.
enum TokenEstimator {
    /// Estimates token count for a single string.
    static func estimate(_ text: String) -> Int {
        EiginSDK.Experimental.Context.estimate(text)
    }

    /// Estimates messages including framing, tools, and validated reasoning.
    static func estimate(messages: [ChatMessage]) -> Int {
        EiginSDK.Experimental.Context.estimate(messages: ContextSDK.messages(messages))
    }

    /// Estimates token count for tool definitions.
    static func estimate(toolDefinitions: [ToolDefinition]) -> Int {
        guard let data = try? JSONEncoder().encode(toolDefinitions) else { return Int.max }
        return EiginSDK.Experimental.Context.estimate(
            serializedTools: String(decoding: data, as: UTF8.self),
            toolCount: UInt64(toolDefinitions.count)
        )
    }

    /// Estimates messages and tool definitions together.
    static func estimateRequest(
        messages: [ChatMessage],
        toolDefinitions: [ToolDefinition]?,
        model: String? = nil
    ) -> Int {
        let definitions = toolDefinitions ?? []
        guard let data = try? JSONEncoder().encode(definitions) else { return Int.max }
        return EiginSDK.Experimental.Context.estimateRequest(
            messages: ContextSDK.messages(messages, model: model),
            serializedTools: String(decoding: data, as: UTF8.self),
            toolCount: UInt64(definitions.count)
        )
    }
}
