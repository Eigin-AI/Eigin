@testable import Eigin
import Foundation
import Testing

@Suite("CompactionService")
struct CompactionServiceTests {
    private let dummyURL = "https://example.com"
    private let dummyProviderID = UUID()
    private let dummyModel = "test-model"

    // MARK: - compact()

    private func summaryEvents(_ text: String) -> [ChatStreamEvent] {
        [.contentDelta(text), .finished(.stop)]
    }

    /// Turn-payload shape used by the compact tests: [system, user].
    private func turnPayload() -> [ChatMessage] {
        [
            ChatMessage(role: "system", content: "You are a helpful agent."),
            ChatMessage(role: "user", content: "Hello world"),
        ]
    }

    @Test func compactReturnsSummary() async {
        let fake = FakeChatService()
        // Produce a 60+ char summary inside the required tags.
        let summary = "The user discussed project architecture and deployment plans in detail."
        fake.enqueueEventStream(summaryEvents(
            "<conversation_summary>\n\(summary)\n</conversation_summary>"
        ))

        let outcome = await CompactionService.compact(
            apiMessages: turnPayload(),
            coveredCount: 1,
            retainedCount: 0,
            contextWindow: 1_000_000,
            baseURL: dummyURL,
            providerID: dummyProviderID,
            model: dummyModel,
            chatService: fake
        )

        #expect(outcome.summary == summary)
        #expect(!outcome.droppedAllCovered)
    }

    @Test func compactRequestContinuesTheTurnPayload() async {
        // The request must be the turn's exact payload plus only the summarise
        // suffix — that's what lets a provider's prompt cache cover the whole
        // conversation instead of re-prefilling a rebuilt transcript.
        let fake = FakeChatService()
        let summary = "The user discussed project architecture and deployment plans in detail."
        fake.enqueueEventStream(summaryEvents(
            "<conversation_summary>\n\(summary)\n</conversation_summary>"
        ))

        let payload = turnPayload()
        let outcome = await CompactionService.compact(
            apiMessages: payload,
            coveredCount: 1,
            retainedCount: 1,
            contextWindow: 1_000_000,
            baseURL: dummyURL,
            providerID: dummyProviderID,
            model: dummyModel,
            chatService: fake
        )
        #expect(outcome.summary != nil)

        let request = fake.capturedEventMessages
        // [system, user, assistant ack, user instruction]
        #expect(request.count == payload.count + 2)
        #expect(request.map(\.role) == ["system", "user", "assistant", "user"])
        // Prefix is byte-identical to the turn payload.
        #expect(request.prefix(payload.count).map(\.localID) == payload.map(\.localID))
        // The instruction names the retained count and demands the tagged block.
        #expect(request.last?.content?.contains("final 1 messages") == true)
        #expect(request.last?.content?.contains("<conversation_summary>") == true)
    }

    @Test func compactSkipsAckWhenPayloadEndsOnAssistant() async {
        let fake = FakeChatService()
        let summary = "The user discussed project architecture and deployment plans in detail."
        fake.enqueueEventStream(summaryEvents(
            "<conversation_summary>\n\(summary)\n</conversation_summary>"
        ))

        let payload: [ChatMessage] = [
            ChatMessage(role: "system", content: "System"),
            ChatMessage(role: "user", content: "Hi"),
            ChatMessage(role: "assistant", content: "Hello"),
        ]
        _ = await CompactionService.compact(
            apiMessages: payload,
            coveredCount: 2,
            retainedCount: 0,
            contextWindow: 1_000_000,
            baseURL: dummyURL,
            providerID: dummyProviderID,
            model: dummyModel,
            chatService: fake
        )

        // [system, user, assistant, user instruction] — no ack needed.
        let request = fake.capturedEventMessages
        #expect(request.count == payload.count + 1)
        #expect(request.last?.role == "user")
    }

    @Test func compactUsesEventStreamWithTurnTools() async {
        // Tools ride along so the request serialises identically to the turn's —
        // some providers key their prompt cache on the tool definitions too.
        let fake = FakeChatService()
        let summary = "The user discussed project architecture and deployment plans in detail."
        fake.enqueueEventStream(summaryEvents(
            "<conversation_summary>\n\(summary)\n</conversation_summary>"
        ))

        let tool = ToolDefinition(name: "web_search", description: "Search", parameters: JSONSchema(
            type: "object",
            properties: [:],
            required: []
        ))
        _ = await CompactionService.compact(
            apiMessages: turnPayload(),
            coveredCount: 1,
            retainedCount: 0,
            contextWindow: 1_000_000,
            tools: [tool],
            cacheKey: "chat-1",
            baseURL: dummyURL,
            providerID: dummyProviderID,
            model: dummyModel,
            chatService: fake
        )

        #expect(fake.capturedEventTools?.map(\.function.name) == ["web_search"])
        #expect(fake.capturedEventCacheKey == "chat-1")
    }

    @Test func compactReportsProgressPhases() async {
        let fake = FakeChatService()
        let summary = "The user discussed project architecture and deployment plans in detail."
        fake.enqueueEventStream(summaryEvents(
            "<conversation_summary>\n\(summary)\n</conversation_summary>"
        ))

        let collector = PhaseCollector()
        let onProgress: @Sendable (CompactionPhase) -> Void = { phase in
            switch phase {
            case .waiting: collector.append("waiting")
            case .streaming: collector.append("streaming")
            case .finalizing: collector.append("finalizing")
            }
        }

        _ = await CompactionService.compact(
            apiMessages: turnPayload(),
            coveredCount: 1,
            retainedCount: 0,
            contextWindow: 1_000_000,
            baseURL: dummyURL,
            providerID: dummyProviderID,
            model: dummyModel,
            chatService: fake,
            onProgress: onProgress
        )

        let phases = collector.values
        #expect(phases.first == "waiting")
        #expect(phases.last == "finalizing")
        #expect(phases.contains("streaming"))
    }

    @Test func compactRejectsTooShortSummary() async {
        let fake = FakeChatService()
        fake.enqueueEventStream(summaryEvents("Short."))

        let outcome = await CompactionService.compact(
            apiMessages: turnPayload(),
            coveredCount: 1,
            retainedCount: 0,
            contextWindow: 1_000_000,
            baseURL: dummyURL,
            providerID: dummyProviderID,
            model: dummyModel,
            chatService: fake
        )

        #expect(outcome.summary == nil)
        #expect(!outcome.droppedAllCovered)
    }

    @Test func compactReturnsNilOnStreamError() async {
        let fake = FakeChatService()
        fake.throwOnEventStream(NSError(domain: "test", code: 1))

        let outcome = await CompactionService.compact(
            apiMessages: turnPayload(),
            coveredCount: 1,
            retainedCount: 0,
            contextWindow: 1_000_000,
            baseURL: dummyURL,
            providerID: dummyProviderID,
            model: dummyModel,
            chatService: fake
        )

        #expect(outcome.summary == nil)
        #expect(!outcome.droppedAllCovered)
    }

    // MARK: - Window fit

    /// Builds a ~100-token message (400 chars / 4, plus 4 framing overhead).
    private func sized(_ prefix: String) -> ChatMessage {
        ChatMessage(role: "user", content: prefix + String(repeating: "x", count: 390))
    }

    @Test func compactTruncatesCoveredHistoryToFitWindow() async {
        // A small window forces the covered history down; the dropped oldest
        // messages must not reach the request.
        let fake = FakeChatService()
        let summary = "The user discussed project architecture and deployment plans in detail."
        fake.enqueueEventStream(summaryEvents(
            "<conversation_summary>\n\(summary)\n</conversation_summary>"
        ))

        // 30 covered messages of ~100 tokens each: far past what the window
        // leaves for them after the instruction and retained tail.
        let covered = (0 ..< 30).map { sized("OLD \($0) ") }
        let payload = [
            ChatMessage(role: "system", content: "System"),
        ] + covered + [sized("RETAINED ")]
        let outcome = await CompactionService.compact(
            apiMessages: payload,
            coveredCount: 30,
            retainedCount: 1,
            contextWindow: 4000,
            baseURL: dummyURL,
            providerID: dummyProviderID,
            model: dummyModel,
            chatService: fake
        )

        #expect(outcome.summary != nil)
        let requestText = fake.capturedEventMessages.map { $0.content ?? "" }.joined()
        // The oldest covered messages were dropped from the request (trailing
        // space avoids matching "OLD 10" when checking "OLD 1")…
        #expect(!requestText.contains("OLD 0 "))
        #expect(!requestText.contains("OLD 9 "))
        // …the retained tail and the newest covered messages are still there.
        #expect(requestText.contains("OLD 29 "))
        #expect(requestText.contains("RETAINED"))
    }

    @Test func compactDroppedAllCoveredWhenWindowImpossiblySmall() async {
        // Retained + system already blow the budget — there is no room to
        // summarise anything, and no stream call is made.
        let fake = FakeChatService()
        let payload = [
            ChatMessage(role: "system", content: String(repeating: "s", count: 4000)),
            sized("OLD "),
            sized("RETAINED "),
        ]
        let outcome = await CompactionService.compact(
            apiMessages: payload,
            coveredCount: 1,
            retainedCount: 1,
            contextWindow: 1000,
            baseURL: dummyURL,
            providerID: dummyProviderID,
            model: dummyModel,
            chatService: fake
        )

        #expect(outcome.summary == nil)
        #expect(outcome.droppedAllCovered)
        #expect(fake.capturedEventMessages.isEmpty)
    }

    // MARK: - parseSummary()

    @Test func parseSummaryExtractsTaggedBlock() {
        let inner = "The conversation covered Swift concurrency in depth with examples."
        let raw = "Sure, here is the summary.\n<conversation_summary>\n\(inner)\n</conversation_summary>\nDone."
        #expect(CompactionService.parseSummary(raw) == inner)
    }

    @Test func parseSummaryRejectsUntaggedReply() {
        // In-conversation, an untagged reply is likely the model answering the
        // user — it must not become the summary.
        #expect(CompactionService.parseSummary(
            "The conversation covered Swift concurrency in depth with examples."
        ) == nil)
    }

    @Test func parseSummaryAcceptsMissingCloseTag() {
        // Streams can end before the closing tag arrives; the body after the
        // opening tag is still the summary.
        let inner = "The conversation covered Swift concurrency in depth with examples."
        #expect(CompactionService.parseSummary(
            "<conversation_summary>\n\(inner)"
        ) == inner)
    }

    @Test func parseSummaryRejectsTooShort() {
        #expect(CompactionService.parseSummary("Too short.") == nil)
        #expect(CompactionService.parseSummary(
            "<conversation_summary>short</conversation_summary>"
        ) == nil)
    }

    // MARK: - truncateForBudget()

    @Test func truncateKeepsNewestMessages() {
        let messages = (0 ..< 5).map { _ in
            ChatMessage(role: "user", content: String(repeating: "word ", count: 20))
        }
        // Each message: ~100 chars / 4 = 25 tokens + 4 framing = 29 tokens
        // Budget of 60 tokens should fit ~2 messages
        let result = CompactionService.truncateForBudget(messages: messages, tokenBudget: 60)

        #expect(result.count < messages.count)
        #expect(result.count >= 1)
        // Should be the newest messages
        #expect(result.last?.localID == messages.last?.localID)
    }

    @Test func truncateReturnsAllWhenWithinBudget() {
        let messages = [
            ChatMessage(role: "user", content: "Hello"),
            ChatMessage(role: "assistant", content: "Hi there"),
        ]
        // Large budget — everything fits
        let result = CompactionService.truncateForBudget(messages: messages, tokenBudget: 100_000)

        #expect(result.count == messages.count)
    }

    @Test func truncateReturnsEmptyWhenNothingFits() {
        let messages = [
            ChatMessage(role: "user", content: "Hello world"),
        ]
        let result = CompactionService.truncateForBudget(messages: messages, tokenBudget: 0)

        #expect(result.isEmpty)
    }

    // MARK: - windowedForBudget()

    /// Builds a message whose estimated cost (content tokens + 4 framing) equals
    /// `tokens`. `TokenEstimator.estimate` is `max(1, chars / 4)`, so
    /// `4 * (tokens - 4)` characters yields `tokens - 4` content tokens.
    private func sizedMessage(tokens: Int) -> ChatMessage {
        let contentTokens = max(1, tokens - 4)
        return ChatMessage(role: "user", content: String(repeating: "x", count: contentTokens * 4))
    }

    private func tokenCount(_ messages: [ChatMessage]) -> Int {
        messages.reduce(0) { $0 + TokenEstimator.estimate($1.content ?? "") + 4 }
    }

    @Test func windowReturnsAllWhenUnderHighMark() {
        let messages = (0 ..< 5).map { _ in sizedMessage(tokens: 100) } // 500 tokens total
        let result = CompactionService.windowedForBudget(
            messages: messages, highMark: 1000, lowMark: 500
        )
        #expect(result.map(\.localID) == messages.map(\.localID))
    }

    @Test func windowEmptyInputReturnsEmpty() {
        #expect(
            CompactionService.windowedForBudget(messages: [], highMark: 1000, lowMark: 500).isEmpty
        )
    }

    @Test func windowNeverExceedsHighMark() {
        let all = (0 ..< 40).map { _ in sizedMessage(tokens: 100) }
        for n in 1 ... all.count {
            let result = CompactionService.windowedForBudget(
                messages: Array(all[0 ..< n]), highMark: 1000, lowMark: 500
            )
            #expect(!result.isEmpty)
            // A single message can't be split, so the bound only applies when we
            // actually kept more than one.
            if result.count > 1 {
                #expect(tokenCount(result) <= 1000)
            }
        }
    }

    @Test func windowKeepsContiguousNewestSuffix() {
        let messages = (0 ..< 30).map { _ in sizedMessage(tokens: 100) }
        let result = CompactionService.windowedForBudget(
            messages: messages, highMark: 1000, lowMark: 500
        )
        #expect(result.last?.localID == messages.last?.localID)
        let resultIDs = result.map(\.localID)
        let tail = Array(messages.map(\.localID).suffix(resultIDs.count))
        #expect(resultIDs == tail)
    }

    @Test func windowKeepsAtLeastLastMessageWhenOversized() {
        let messages = [sizedMessage(tokens: 50), sizedMessage(tokens: 5000)]
        let result = CompactionService.windowedForBudget(
            messages: messages, highMark: 1000, lowMark: 500
        )
        #expect(result.count == 1)
        #expect(result.first?.localID == messages.last?.localID)
    }

    @Test func windowIsDeterministic() {
        let messages = (0 ..< 25).map { _ in sizedMessage(tokens: 100) }
        let a = CompactionService.windowedForBudget(
            messages: messages,
            highMark: 1000,
            lowMark: 500
        )
        let b = CompactionService.windowedForBudget(
            messages: messages,
            highMark: 1000,
            lowMark: 500
        )
        #expect(a.map(\.localID) == b.map(\.localID))
    }

    /// The core hysteresis property: as the conversation grows one message at a
    /// time, the oldest kept message stays fixed for several turns and only jumps
    /// at step boundaries — so the prefix (and the on-device KV cache) is reused
    /// between jumps. With 100-token messages, high 1000 / low 500 (step 500),
    /// the boundary advances exactly every 5 turns.
    @Test func windowBoundaryIsStableBetweenSteps() {
        let all = (0 ..< 30).map { _ in sizedMessage(tokens: 100) }

        func oldestKeptIndex(messageCount n: Int) -> Int {
            let result = CompactionService.windowedForBudget(
                messages: Array(all[0 ..< n]), highMark: 1000, lowMark: 500
            )
            let oldestID = result.first!.localID
            return all.firstIndex { $0.localID == oldestID }!
        }

        for n in 11 ... 14 {
            #expect(oldestKeptIndex(messageCount: n) == 5)
        }
        for n in 15 ... 19 {
            #expect(oldestKeptIndex(messageCount: n) == 10)
        }
        for n in 20 ... 24 {
            #expect(oldestKeptIndex(messageCount: n) == 15)
        }
    }

    @Test func windowBoundaryAdvancesMonotonicallyAndInfrequently() throws {
        let all = (0 ..< 60).map { _ in sizedMessage(tokens: 100) }
        var previousIndex = 0
        var changes = 0
        for n in 1 ... all.count {
            let result = CompactionService.windowedForBudget(
                messages: Array(all[0 ..< n]), highMark: 1000, lowMark: 500
            )
            let oldestID = try #require(result.first?.localID)
            let index = try #require(all.firstIndex { $0.localID == oldestID })
            #expect(index >= previousIndex) // boundary never moves backward
            if index != previousIndex { changes += 1 }
            previousIndex = index
        }
        // Step 500 / 100 per turn ⇒ ~1 change per 5 turns, far below the 60 turns.
        // A plain per-turn truncation would change on nearly every turn.
        #expect(changes < 20)
    }

    // MARK: - retainedTail()

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

    private func assistantWithTools(ids: [String]) -> ChatMessage {
        ChatMessage(role: "assistant", toolCalls: ids.map {
            ToolCall(id: $0, type: "function", function: .init(name: "test", arguments: "{}"))
        })
    }

    private func toolResult(id: String) -> ChatMessage {
        ChatMessage(role: "tool", content: "result", toolCallID: id)
    }

    @Test func retainedTailReturnsAllWhenWithinBudget() {
        let messages = [user("hello"), assistant("hi"), user("more"), assistant("sure")]
        let result = CompactionService.retainedTail(messages: messages, tokenBudget: 100_000)
        #expect(result.map(\.localID) == messages.map(\.localID))
    }

    @Test func retainedTailKeepsMinimumTurnsEvenWhenOverBudget() {
        // Two oversized turns exceed the budget, but the minimum keeps them anyway.
        let messages = [
            user("old"), assistant("old reply"),
            user(String(repeating: "x", count: 4000)), assistant(String(
                repeating: "x",
                count: 4000
            )),
            user(String(repeating: "x", count: 4000)), assistant(String(
                repeating: "x",
                count: 4000
            )),
        ]
        let result = CompactionService.retainedTail(messages: messages, tokenBudget: 100)
        #expect(result.count == 4)
        #expect(result.first?.localID == messages[2].localID)
    }

    @Test func retainedTailExtendsWithShortTurnsUpToBudget() {
        // 10 turns of ~44 tokens each (~440 total). A 250-token budget keeps 2
        // minimum turns, then packs in as many further turns as fit.
        var messages: [ChatMessage] = []
        for i in 0 ..< 10 {
            messages.append(user("hello \(i)"))
            messages.append(assistant("reply \(i)"))
        }
        let result = CompactionService.retainedTail(messages: messages, tokenBudget: 250)
        #expect(result.count > 4)
        #expect(result.count <= messages.count)
        // Contiguous newest suffix, cut on a turn boundary (even count).
        #expect(result.last?.localID == messages.last?.localID)
        #expect(result.first?.role == "user")
        #expect(result.count.isMultiple(of: 2))
    }

    @Test func retainedTailNeverSplitsToolRound() {
        let messages = [
            user("first"), assistant("reply"),
            sizedMessage(tokens: 1000), // oversized turn blows the budget mid-walk
            user("go"),
            assistantWithTools(ids: ["A"]),
            toolResult(id: "A"),
            assistant("done"),
            user("again"), assistant("final"),
        ]
        // The budget stops the walk before the oversized turn, keeping the tool
        // round that follows it fully intact.
        let result = CompactionService.retainedTail(messages: messages, tokenBudget: 100)
        #expect(result.map(\.localID) == Array(messages[3...].map(\.localID)))
    }

    @Test func retainedTailStopsAtSyntheticSummaryCarrier() {
        let carrier = ChatMessage(
            role: "user",
            content: "<conversation_summary>\nOlder conversation summary.\n</conversation_summary>"
        )
        let messages = [
            carrier, assistant("Understood"),
            user("hello"), assistant("hi"),
            user("more"), assistant("sure"),
        ]
        let result = CompactionService.retainedTail(messages: messages, tokenBudget: 100_000)
        #expect(result.map(\.localID) == Array(messages[2...].map(\.localID)))
    }

    @Test func retainedTailEmptyWhenNoUserMessages() {
        let messages = [assistant("a"), assistant("b")]
        #expect(CompactionService.retainedTail(messages: messages, tokenBudget: 100).isEmpty)
    }

    // MARK: - Retained tail in the instruction

    @Test func instructionTellsModelToSkipRetainedTail() async {
        let fake = FakeChatService()
        let summary = "The user discussed project architecture and deployment plans in detail."
        fake.enqueueEventStream(summaryEvents(
            "<conversation_summary>\n\(summary)\n</conversation_summary>"
        ))

        _ = await CompactionService.compact(
            apiMessages: turnPayload(),
            coveredCount: 1,
            retainedCount: 12,
            contextWindow: 1_000_000,
            baseURL: dummyURL,
            providerID: dummyProviderID,
            model: dummyModel,
            chatService: fake
        )

        let instruction = fake.capturedEventMessages.last?.content ?? ""
        #expect(instruction.contains("final 12 messages"))
        #expect(instruction.contains("<conversation_summary>"))
    }

    // MARK: - Small-context budget

    @Test("the on-device budget reserves that model's output, not the one it replaced")
    func smallContextBudgetUsesTheRunningModel() async throws {
        // An offline turn runs on the on-device model while the agent still points at the
        // cloud model it will return to. Sizing the reservation from the cloud model's
        // 128k output leaves a negative budget, which silently strips the conversation
        // down to a single message.
        let onDevice = "gemma-4-e2b"
        let contextWindow = try #require(KnownModelCatalog.lookup(onDevice)?.contextWindow)

        var messages = [ChatMessage(role: "system", content: "You are a helpful agent.")]
        for i in 0 ..< 16 {
            messages.append(ChatMessage(
                role: i.isMultiple(of: 2) ? "user" : "assistant",
                content: "Message number \(i)"
            ))
        }

        let result = await MessagePipeline.compactIfNeeded(
            apiMessages: messages,
            estimatedTokens: TokenEstimator.estimate(messages: messages),
            contextWindow: contextWindow,
            baseURL: dummyURL,
            providerID: dummyProviderID,
            model: onDevice,
            chatService: FakeChatService()
        )

        // A short conversation fits the on-device window, so nothing is dropped.
        #expect(result.apiMessages.count == messages.count)
        #expect(result.summary == nil)
    }
}

// MARK: - Helpers

/// Thread-safe collector for progress phase strings.
private final class PhaseCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var _values: [String] = []

    func append(_ value: String) {
        lock.withLock { _values.append(value) }
    }

    var values: [String] {
        lock.withLock { _values }
    }
}
