@testable import Eigin
import Foundation

/// A fake ToolExecutor that records calls and returns canned results.
final class FakeToolExecutor: ToolExecutor, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [ToolCall] = []
    private var _results: [String: ToolResult] = [:]

    /// Recorded tool calls in order.
    var calls: [ToolCall] {
        lock.withLock { _calls }
    }

    /// Register a canned result for a tool call ID.
    func setResult(for toolCallID: String, content: String, isError: Bool = false) {
        lock.withLock {
            _results[toolCallID] = ToolResult(
                toolCallID: toolCallID,
                content: content,
                isError: isError
            )
        }
    }

    @MainActor func execute(_ toolCall: ToolCall, agent: Agent) async -> ToolResult {
        let result = lock.withLock {
            _calls.append(toolCall)
            return _results[toolCall.id]
        }

        return result ?? ToolResult(
            toolCallID: toolCall.id,
            content: "{\"result\":\"OK\"}",
            isError: false
        )
    }
}
