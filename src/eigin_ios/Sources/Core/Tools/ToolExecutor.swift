import Foundation

/// The result of executing a single tool call.
struct ToolResult {
    let toolCallID: String
    let content: String
    let isError: Bool
}

/// Executes tool calls against an Agent model.
protocol ToolExecutor: Sendable {
    @MainActor func execute(_ toolCall: ToolCall, agent: Agent) async -> ToolResult
}
