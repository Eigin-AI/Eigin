@testable import Eigin
import Testing

@Suite("ChatItem.buildItems tool grouping")
struct ChatItemBuildTests {
    // MARK: - Helpers

    private func toolCall(id: String, name: String = "test_tool") -> ToolCall {
        ToolCall(id: id, type: "function", function: .init(name: name, arguments: "{}"))
    }

    @MainActor
    private func buildItems(from messages: [ChatMessage]) -> [ChatItem] {
        let loop = AgenticChatLoop(isBootstrap: false)
        return ChatItem.buildItems(from: messages, chatLoop: loop, chatError: nil)
    }

    // MARK: - Tests

    @Test("Single round with multiple tool calls produces one group")
    @MainActor
    func singleRoundToolGroup() {
        let messages: [ChatMessage] = [
            ChatMessage(
                role: "assistant",
                toolCalls: [toolCall(id: "a"), toolCall(id: "b")],
                localID: "1"
            ),
            ChatMessage(role: "tool", content: "ok", toolCallID: "a", localID: "r1"),
            ChatMessage(role: "tool", content: "ok", toolCallID: "b", localID: "r2"),
            ChatMessage(role: "assistant", content: "Done", localID: "2"),
        ]
        let items = buildItems(from: messages)
        let groups = items.filter { if case .toolGroup = $0 { true } else { false } }
        #expect(groups.count == 1)
        if case .toolGroup(_, let tools) = groups.first {
            #expect(tools.count == 2)
        }
    }

    @Test("Consecutive tool-only rounds merge into one group")
    @MainActor
    func consecutiveToolRoundsMerge() {
        let messages: [ChatMessage] = [
            // Round 1: tool calls, no prose
            ChatMessage(role: "assistant", toolCalls: [toolCall(id: "a")], localID: "1"),
            ChatMessage(role: "tool", content: "ok", toolCallID: "a", localID: "r1"),
            // Round 2: tool calls, no prose
            ChatMessage(
                role: "assistant",
                toolCalls: [toolCall(id: "b"), toolCall(id: "c")],
                localID: "2"
            ),
            ChatMessage(role: "tool", content: "ok", toolCallID: "b", localID: "r2"),
            ChatMessage(role: "tool", content: "ok", toolCallID: "c", localID: "r3"),
            // Round 3: tool calls, no prose
            ChatMessage(role: "assistant", toolCalls: [toolCall(id: "d")], localID: "3"),
            ChatMessage(role: "tool", content: "ok", toolCallID: "d", localID: "r4"),
            // Final response with text
            ChatMessage(role: "assistant", content: "All done", localID: "4"),
        ]
        let items = buildItems(from: messages)
        let groups = items.filter { if case .toolGroup = $0 { true } else { false } }
        #expect(groups.count == 1)
        if case .toolGroup(_, let tools) = groups.first {
            #expect(tools.count == 4)
            #expect(tools.map(\.id) == ["a", "b", "c", "d"])
        }
    }

    @Test("Prose between tool rounds breaks the group")
    @MainActor
    func proseBreaksToolGroup() {
        let messages: [ChatMessage] = [
            // Round 1
            ChatMessage(role: "assistant", toolCalls: [toolCall(id: "a")], localID: "1"),
            ChatMessage(role: "tool", content: "ok", toolCallID: "a", localID: "r1"),
            // Prose separates the groups
            ChatMessage(
                role: "assistant",
                content: "Let me try something else",
                toolCalls: [toolCall(id: "b")],
                localID: "2"
            ),
            ChatMessage(role: "tool", content: "ok", toolCallID: "b", localID: "r2"),
            // Final
            ChatMessage(role: "assistant", content: "Done", localID: "3"),
        ]
        let items = buildItems(from: messages)
        let groups = items.filter { if case .toolGroup = $0 { true } else { false } }
        #expect(groups.count == 2)
    }

    @Test("User message between tool rounds breaks the group")
    @MainActor
    func userMessageBreaksToolGroup() {
        let messages: [ChatMessage] = [
            ChatMessage(role: "assistant", toolCalls: [toolCall(id: "a")], localID: "1"),
            ChatMessage(role: "tool", content: "ok", toolCallID: "a", localID: "r1"),
            ChatMessage(role: "user", content: "Stop", localID: "u1"),
            ChatMessage(role: "assistant", toolCalls: [toolCall(id: "b")], localID: "2"),
            ChatMessage(role: "tool", content: "ok", toolCallID: "b", localID: "r2"),
            ChatMessage(role: "assistant", content: "Done", localID: "3"),
        ]
        let items = buildItems(from: messages)
        let groups = items.filter { if case .toolGroup = $0 { true } else { false } }
        #expect(groups.count == 2)
    }
}
