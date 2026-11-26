public extension EiginSDK.Experimental.Agent {
    /// Platform capabilities used by a complete turn.
    protocol TurnHost: Sendable {
        /// Prepares platform request capabilities from SDK-owned context.
        func prepare(_ context: ChatContext, inline: InlineTools) async throws -> PreparedRequest
        /// Applies host permissions and executes a tool.
        func executeTool(_ call: EiginSDK.Experimental.Inference.ToolCall) async -> EiginSDK.Experimental.Inference.LocalToolResult
        /// Refreshes the execution registry and returns current tool definitions.
        func refreshTools() async -> [EiginSDK.Experimental.Inference.ToolDefinition]?
        /// Reports explicit application completion independently of cancellation.
        func completionRequested() async -> Bool
        /// Classifies a request failure for turn recovery.
        func classifyFailure(_ error: EiginSDK.Experimental.Inference.RequestFailure) -> TurnFailure
    }

    /// Presentation work the turn waits for before continuing.
    protocol TurnPresentation: Sendable {
        /// Ends the prose segment and prepares presentation for a cloud tool batch.
        func finishToolProse(hasProse: Bool) async
        /// Completes presentation handoff before tool execution.
        func beforeTool(_ call: EiginSDK.Experimental.Inference.ToolCall) async
        /// Restores presentation before admitting the completed result.
        func afterTool() async
        /// Finishes displayed output before completion or recovery.
        func drain() async
    }
}

public extension EiginSDK.Experimental.Agent.TurnHost {
    func completionRequested() async -> Bool {
        false
    }
}

public extension EiginSDK.Experimental.Agent.TurnPresentation {
    func finishToolProse(hasProse _: Bool) async {}
    func beforeTool(_: EiginSDK.Experimental.Inference.ToolCall) async {}
    func afterTool() async {}
    func drain() async {}
}
