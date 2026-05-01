@testable import Eigin
import Foundation
import Testing

@Suite("MessagePipeline.repairSequence")
struct MessagePipelineTests {
    // MARK: - Helpers

    private func toolCall(id: String, name: String = "test") -> ToolCall {
        ToolCall(id: id, type: "function", function: .init(name: name, arguments: "{}"))
    }

    private func assistant(_ content: String = "") -> ChatMessage {
        ChatMessage(role: "assistant", content: content)
    }

    private func assistantWithTools(_ content: String? = nil, ids: [String]) -> ChatMessage {
        ChatMessage(
            role: "assistant",
            content: content,
            toolCalls: ids.map { toolCall(id: $0) }
        )
    }

    private func toolResult(id: String) -> ChatMessage {
        ChatMessage(role: "tool", content: "result", toolCallID: id)
    }

    private func user(_ content: String = "hi") -> ChatMessage {
        ChatMessage(role: "user", content: content)
    }

    // MARK: - Tests

    @Test func cleanConversationUnchanged() {
        let input = [user(), assistant("hello"), user("more"), assistant("sure")]
        let result = MessagePipeline.repairSequence(input)
        #expect(result.count == 4)
        #expect(result.map(\.role) == ["user", "assistant", "user", "assistant"])
    }

    @Test func completeRoundKept() {
        let input = [assistantWithTools(ids: ["A"]), toolResult(id: "A")]
        let result = MessagePipeline.repairSequence(input)
        #expect(result.count == 2)
        #expect(result[0].toolCalls?.first?.id == "A")
        #expect(result[1].toolCallID == "A")
    }

    @Test func completeMultiToolRoundKept() {
        let input = [
            assistantWithTools(ids: ["A", "B"]),
            toolResult(id: "A"),
            toolResult(id: "B"),
        ]
        let result = MessagePipeline.repairSequence(input)
        #expect(result.count == 3)
    }

    @Test func orphanedAssistantDropped() {
        let input = [user(), assistantWithTools(ids: ["A"]), user()]
        let result = MessagePipeline.repairSequence(input)
        #expect(result.count == 2)
        #expect(result.map(\.role) == ["user", "user"])
    }

    @Test func partialResultsDropped() {
        let input = [assistantWithTools(ids: ["A", "B"]), toolResult(id: "A")]
        let result = MessagePipeline.repairSequence(input)
        #expect(result.isEmpty)
    }

    @Test func orphanedAtEndDropped() {
        let input = [user(), assistant("plain"), assistantWithTools(ids: ["A"])]
        let result = MessagePipeline.repairSequence(input)
        #expect(result.count == 2)
        #expect(result.map(\.role) == ["user", "assistant"])
    }

    @Test func mixedGoodAndBad() {
        let input = [
            user(),
            assistantWithTools(ids: ["A"]),
            toolResult(id: "A"),
            assistantWithTools(ids: ["B"]),
            user(),
        ]
        let result = MessagePipeline.repairSequence(input)
        #expect(result.count == 4)
        #expect(result.map(\.role) == ["user", "assistant", "tool", "user"])
    }

    @Test func multipleCompleteRounds() {
        let input = [
            assistantWithTools(ids: ["A"]),
            toolResult(id: "A"),
            assistantWithTools(ids: ["B"]),
            toolResult(id: "B"),
        ]
        let result = MessagePipeline.repairSequence(input)
        #expect(result.count == 4)
    }

    @Test func emptyInput() {
        let result = MessagePipeline.repairSequence([])
        #expect(result.isEmpty)
    }

    @Test func assistantWithContentAndToolCalls_complete() {
        let input = [
            assistantWithTools("thinking", ids: ["A"]),
            toolResult(id: "A"),
        ]
        let result = MessagePipeline.repairSequence(input)
        #expect(result.count == 2)
        #expect(result[0].content == "thinking")
        #expect(result[0].toolCalls?.first?.id == "A")
    }

    @Test func assistantWithContentAndToolCalls_orphaned() {
        let input = [assistantWithTools("thinking", ids: ["A"])]
        let result = MessagePipeline.repairSequence(input)
        #expect(result.isEmpty)
    }

    // MARK: - Stray tool results (e.g. after compaction ate the assistant)

    @Test func strayToolResultsAtStartDropped() {
        let input = [toolResult(id: "A"), toolResult(id: "B"), user(), assistant("hi")]
        let result = MessagePipeline.repairSequence(input)
        #expect(result.count == 2)
        #expect(result.map(\.role) == ["user", "assistant"])
    }

    @Test func strayToolResultAfterCompactionSummary() {
        var summary = ChatMessage(role: "system", content: "Summary of earlier conversation")
        summary.isCompactionSummary = true
        let input = [summary, toolResult(id: "A"), user("hello")]
        let result = MessagePipeline.repairSequence(input)
        #expect(result.count == 2)
        #expect(result[0].role == "system")
        #expect(result[1].role == "user")
    }

    @Test func strayToolResultBetweenValidRounds() {
        // The stray tool(Z) is consumed by the scanner as part of the first group's
        // tool messages, making foundIDs={A,Z} != expectedIDs={A}, so the first
        // round is dropped. The second round is valid and kept.
        let input = [
            assistantWithTools(ids: ["A"]),
            toolResult(id: "A"),
            toolResult(id: "Z"), // stray — no assistant owns Z
            assistantWithTools(ids: ["B"]),
            toolResult(id: "B"),
        ]
        let result = MessagePipeline.repairSequence(input)
        #expect(result.count == 2)
        #expect(result.map(\.role) == ["assistant", "tool"])
        #expect(result[0].toolCalls?.first?.id == "B")
    }

    // MARK: - Tool-call rounds after system messages (compaction boundary)

    @Test func completeRoundAfterCompactionSummaryDropped() {
        // Gemini rejects function calls that don't follow a user or tool-response turn.
        // After compaction, a tool-call round may sit right after the summary — drop it.
        var summary = ChatMessage(role: "system", content: "Summary")
        summary.isCompactionSummary = true
        let input = [
            summary,
            assistantWithTools(ids: ["A"]),
            toolResult(id: "A"),
            assistant("Here's the result"),
            user("Thanks"),
        ]
        let result = MessagePipeline.repairSequence(input)
        #expect(result.count == 3)
        #expect(result.map(\.role) == ["system", "assistant", "user"])
        #expect(result[1].content == "Here's the result")
    }

    @Test func completeRoundAfterUserKept() {
        // Same round but preceded by a user message — should be kept.
        let input = [
            user("do something"),
            assistantWithTools(ids: ["A"]),
            toolResult(id: "A"),
            assistant("Done"),
        ]
        let result = MessagePipeline.repairSequence(input)
        #expect(result.count == 4)
        #expect(result.map(\.role) == ["user", "assistant", "tool", "assistant"])
    }
}

@Suite("MessagePipeline.slidingWindowCompaction")
struct SlidingWindowCompactionTests {
    @Test func slidingWindowSkipsWhenUnderBudget() async {
        let messages = [
            ChatMessage(role: "system", content: "System"),
            ChatMessage(role: "user", content: "Hi"),
            ChatMessage(role: "assistant", content: "Hello"),
        ]

        let result = await MessagePipeline.compactIfNeeded(
            apiMessages: messages,
            estimatedTokens: 100, // well under 75% of 8192
            contextWindow: 8192,
            baseURL: "local://apple-foundation-model",
            providerID: UUID(),
            model: "apple-foundation-model",
            chatService: PreviewChatService()
        )

        // No compaction needed
        #expect(result.apiMessages.count == messages.count)
    }

    @Test func regularCompactionNotTriggeredForSmallContext() async {
        let messages = [
            ChatMessage(role: "system", content: "System"),
            ChatMessage(role: "user", content: "Hi"),
        ]

        let result = await MessagePipeline.compactIfNeeded(
            apiMessages: messages,
            estimatedTokens: 50,
            contextWindow: 8192,
            needsCompaction: true,
            baseURL: "local://apple-foundation-model",
            providerID: UUID(),
            model: "apple-foundation-model",
            chatService: PreviewChatService()
        )

        #expect(result.summary == nil)
    }
}
