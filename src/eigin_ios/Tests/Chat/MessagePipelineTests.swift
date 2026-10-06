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

@Suite("MessagePipeline.retentionCompaction")
struct RetentionCompactionTests {
    private let dummyURL = "https://example.com"
    private let dummyProviderID = UUID()
    private let dummyModel = "test-model"

    private func user(_ content: String)
        -> ChatMessage
    {
        ChatMessage(role: "user", content: content)
    }

    private func assistant(_ content: String) -> ChatMessage {
        ChatMessage(
            role: "assistant",
            content: content
        )
    }

    /// A ~100-token message: 400 chars / 4, plus 4 framing overhead. Only used
    /// by tests that don't need to identify individual messages.
    private func sizedMessage(tokens: Int) -> ChatMessage {
        let contentTokens = max(1, tokens - 4)
        return ChatMessage(role: "user", content: String(repeating: "x", count: contentTokens * 4))
    }

    private func conversation(turns: Int) -> [ChatMessage] {
        var messages = [ChatMessage(role: "system", content: "You are a helpful agent.")]
        // ~100 tokens per message (400 chars / 4), with a distinct prefix so
        // individual messages are identifiable in the summariser transcript.
        for i in 0 ..< turns {
            messages.append(user("Turn \(i): " + String(repeating: "x", count: 390)))
            messages.append(assistant("Reply \(i): " + String(repeating: "x", count: 390)))
        }
        return messages
    }

    @Test func summaryCoversOlderMessagesAndKeepsRecentTurnsVerbatim() async throws {
        // 30 turns of ~208 tokens per turn: the 5% retained budget of a 100k
        // window (5000 tokens) keeps the most recent ~24 turns verbatim; the
        // older ones are summarised.
        let contextWindow = 100_000
        let messages = conversation(turns: 30)
        let fake = FakeChatService()
        let summary = "The user discussed project architecture and deployment plans in detail."
        fake.enqueueEventStream([
            .contentDelta("<conversation_summary>\n\(summary)\n</conversation_summary>"),
            .finished(.stop),
        ])

        let result = await MessagePipeline.compactIfNeeded(
            apiMessages: messages,
            estimatedTokens: 60000, // past the 50% trigger for a 100k window
            contextWindow: contextWindow,
            baseURL: dummyURL,
            providerID: dummyProviderID,
            model: dummyModel,
            chatService: fake,
            tools: [],
            cacheKey: "chat-1"
        )

        let summaryMessage = try #require(result.summary)

        // [system, summary, retained...]
        let retained = Array(result.apiMessages.dropFirst(2))
        #expect(result.apiMessages.first?.role == "system")
        #expect(result.apiMessages[1].localID == summaryMessage.localID)
        #expect(!retained.isEmpty)
        #expect(summaryMessage.compactionRetainedMessageCount == retained.count)

        // Retained window is the newest verbatim suffix, at least 2 turns.
        #expect(retained.last?.localID == messages.last?.localID)
        #expect(retained.first?.role == "user")
        #expect(retained.count >= 4)

        // The summarise request is the turn's exact payload plus only the
        // summarise suffix — cache-identical prefix, no rebuilt transcript.
        let request = fake.capturedEventMessages
        #expect(request.count == messages.count + 1) // ends on assistant → no ack needed
        #expect(request.prefix(messages.count).map(\.localID) == messages.map(\.localID))
        #expect(request.last?.role == "user")
        #expect(request.last?.content?.contains("<conversation_summary>") == true)
        // Same tools and cache key as the turn.
        #expect(fake.capturedEventTools?.isEmpty == true)
        #expect(fake.capturedEventCacheKey == "chat-1")

        // Post-compaction usage stays well below the trigger threshold.
        let estimate = TokenEstimator.estimateRequest(
            messages: result.apiMessages,
            toolDefinitions: []
        )
        #expect(estimate <
            Int(Double(contextWindow) * MessagePipeline.Compaction.threshold(for: contextWindow)))
    }

    @Test func splitAtLatestSummaryHonoursRetainedCount() {
        var messages = [user("old"), assistant("old reply")]
        var summary = ChatMessage(
            role: "system",
            content: "Summary of earlier conversation:\n\nstuff"
        )
        summary.isCompactionSummary = true
        summary.compactionRetainedMessageCount = 2
        messages.append(summary)
        messages.append(user("new"))

        let (splitSummary, conversation) = MessagePipeline.splitAtLatestSummary(messages)

        #expect(splitSummary == summary.content)
        // The two messages before the summary plus everything after it.
        #expect(conversation.map(\.localID) == [
            messages[0].localID,
            messages[1].localID,
            messages[3].localID,
        ])
    }

    @Test func splitAtLatestSummaryWithoutRetainedCountKeepsLegacyBehaviour() {
        var messages = [user("old"), assistant("old reply")]
        var summary = ChatMessage(
            role: "system",
            content: "Summary of earlier conversation:\n\nstuff"
        )
        summary.isCompactionSummary = true
        messages.append(summary)
        messages.append(user("new"))

        let (splitSummary, conversation) = MessagePipeline.splitAtLatestSummary(messages)

        #expect(splitSummary == summary.content)
        #expect(conversation.map(\.localID) == [messages[3].localID])
    }

    @Test func staleCompactionFlagClearsWellBelowThreshold() async {
        // A failed attempt leaves needsCompaction stuck on. Once the
        // conversation has shrunk well below the threshold, compaction
        // clears the flag instead of retrying forever.
        let contextWindow = 100_000 // threshold 50_000, stale limit 25_000
        let messages = [
            ChatMessage(role: "system", content: "System"),
            user("Hi"),
            assistant("Hello"),
        ]
        let fake = FakeChatService() // would fail loudly if summarisation ran

        let result = await MessagePipeline.compactIfNeeded(
            apiMessages: messages,
            estimatedTokens: 10000, // below the stale limit
            contextWindow: contextWindow,
            needsCompaction: true,
            baseURL: dummyURL,
            providerID: dummyProviderID,
            model: dummyModel,
            chatService: fake
        )

        #expect(result.needsCompaction == false)
        #expect(result.summary == nil)
    }

    @Test func compactionThresholdScalesWithContextWindowSize() async {
        // Windows below 500k trigger at 50% of the context, 500k and above
        // keep the 25% trigger.
        let summary = "The user discussed project architecture and deployment plans in detail."
        let messages = [
            ChatMessage(role: "system", content: "System"),
            user("Hi"),
            assistant("Hello"),
        ]

        func makeFake() -> FakeChatService {
            let fake = FakeChatService()
            fake.enqueueEventStream([
                .contentDelta("<conversation_summary>\n\(summary)\n</conversation_summary>"),
                .finished(.stop),
            ])
            return fake
        }

        // 300k window at 30% usage: below the 50% trigger, so no compaction.
        let smallWindowResult = await MessagePipeline.compactIfNeeded(
            apiMessages: messages,
            estimatedTokens: 90000,
            contextWindow: 300_000,
            baseURL: dummyURL,
            providerID: dummyProviderID,
            model: dummyModel,
            chatService: makeFake(),
            tools: [],
            cacheKey: "chat-1"
        )
        #expect(smallWindowResult.summary == nil)
        #expect(smallWindowResult.needsCompaction == false)

        // 500k window at 26% usage: past the 25% large-window trigger. Needs
        // enough history that the 5% retained budget (25k tokens) doesn't
        // cover the whole conversation — 150 turns of ~208 tokens works.
        let largeWindowConversation = conversation(turns: 150)
        let largeWindowResult = await MessagePipeline.compactIfNeeded(
            apiMessages: largeWindowConversation,
            estimatedTokens: 130_000,
            contextWindow: 500_000,
            baseURL: dummyURL,
            providerID: dummyProviderID,
            model: dummyModel,
            chatService: makeFake(),
            tools: [],
            cacheKey: "chat-1"
        )
        #expect(largeWindowResult.summary != nil)
    }

    @Test func retainedCountReassemblesStoreRowsAfterPersist() {
        // Mirrors the store order after send(): every message — including the
        // triggering user message — is persisted BEFORE the summary row, so the
        // payload's retained tail is the same rows in the store and the count
        // reassembles the payload exactly (no covered message leaks verbatim).
        let covered = [user("c0"), assistant("c1"), user("c2")]
        let retained = [user("r0"), assistant("r1"), user("r2 triggering")]
        var summary = ChatMessage(
            role: "system",
            content: "Summary of earlier conversation:\n\nS"
        )
        summary.isCompactionSummary = true
        summary.compactionRetainedMessageCount = retained.count
        let future = [user("after compaction"), assistant("and the reply")]
        let store = covered + retained + [summary] + future

        let (splitSummary, conversation) = MessagePipeline.splitAtLatestSummary(store)

        #expect(splitSummary == summary.content)
        #expect(conversation.map(\.localID) == retained.map(\.localID) + future.map(\.localID))
    }

    @Test func splitAtLatestSummaryReturnsInputWhenNoSummary() {
        let messages = [user("a"), assistant("b")]
        let (splitSummary, conversation) = MessagePipeline.splitAtLatestSummary(messages)
        #expect(splitSummary == nil)
        #expect(conversation.map(\.localID) == messages.map(\.localID))
    }
}
