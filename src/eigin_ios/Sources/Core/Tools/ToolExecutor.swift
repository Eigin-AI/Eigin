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
    /// Returns the execution mode for a tool by name. Defaults to `.background`.
    func executionMode(for toolName: String) -> ToolExecutionMode
    /// Disclosure for a tool call, for the permission sheet. Defaults to `nil`.
    func disclosure(for toolCall: ToolCall) -> ToolDisclosure?
}

extension ToolExecutor {
    func executionMode(for toolName: String) -> ToolExecutionMode {
        .background
    }

    func disclosure(for toolCall: ToolCall) -> ToolDisclosure? {
        nil
    }
}
