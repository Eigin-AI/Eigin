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

    // MARK: - App message conversion

    @Test func partialMessageKeepsLegacyReconstructionDefaults() throws {
        let call = ToolCall(
            id: "call",
            type: "function",
            function: .init(name: "test", arguments: "{}")
        )
        var message = ChatMessage(
            role: "assistant", content: String(repeating: "x", count: 4000),
            toolCallID: "result", name: "name", toolCalls: [call],
            providerMetadata: ["signature": "value"], attachments: []
        )
        message.isCompactionSummary = true
        message.compactionRetainedMessageCount = 2
        let newest = ChatMessage(role: "user", content: "newest")
        let result = CompactionService.truncateForBudget(
            messages: [message, newest],
            tokenBudget: 40
        )
        let partial = try #require(result.first)
        #expect(result.count == 2)
        #expect(partial.localID != message.localID)
        #expect(partial.content?.hasPrefix("…") == true)
        #expect(partial.role == message.role)
        #expect(partial.toolCallID == message.toolCallID)
        #expect(partial.name == message.name)
        #expect(partial.toolCalls?.first?.id == "call")
        #expect(partial.providerMetadata == nil)
        #expect(partial.attachments == nil)
        #expect(partial.reasoningHistory == nil)
        #expect(!partial.isCompactionSummary)
        #expect(partial.compactionRetainedMessageCount == nil)
        #expect(result.last?.localID == newest.localID)
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
