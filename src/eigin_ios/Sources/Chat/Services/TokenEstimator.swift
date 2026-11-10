import EiginSDK

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
        EiginSDK.Experimental.Context.estimate(toolCount: toolDefinitions.count)
    }

    /// Estimates messages and tool definitions together.
    static func estimateRequest(
        messages: [ChatMessage],
        toolDefinitions: [ToolDefinition]?
    ) -> Int {
        EiginSDK.Experimental.Context.estimateRequest(
            messages: ContextSDK.messages(messages), toolCount: toolDefinitions?.count ?? 0
        )
    }
}
