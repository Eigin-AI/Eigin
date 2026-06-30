@testable import Eigin
import Foundation
import Testing

@Suite("CompactionService")
struct CompactionServiceTests {
    private let dummyURL = "https://example.com"
    private let dummyProviderID = UUID()
    private let dummyModel = "test-model"

    // MARK: - compact()

    @Test func compactReturnsSummary() async {
        let fake = FakeChatService()
        // Produce tokens that together form a 60+ char summary
        let summary = "The user discussed project architecture and deployment plans in detail."
        let tokens = summary.split(separator: " ").map { String($0) + " " }
        fake.enqueueTokens(tokens)

        let result = await CompactionService.compact(
            messages: [ChatMessage(role: "user", content: "Hello world")],
            baseURL: dummyURL,
            providerID: dummyProviderID,
            model: dummyModel,
            chatService: fake
        )

        #expect(result != nil)
        #expect(result == summary.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    @Test func compactReportsProgressPhases() async {
        let fake = FakeChatService()
        let summary = "The user discussed project architecture and deployment plans in detail."
        let tokens = summary.split(separator: " ").map { String($0) + " " }
        fake.enqueueTokens(tokens)

        let collector = PhaseCollector()
        let onProgress: @Sendable (CompactionPhase) -> Void = { phase in
            switch phase {
            case .waiting: collector.append("waiting")
            case .streaming: collector.append("streaming")
            case .finalizing: collector.append("finalizing")
            }
        }

        _ = await CompactionService.compact(
            messages: [ChatMessage(role: "user", content: "Hello world")],
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
        // Produce tokens totalling < 50 chars
        fake.enqueueTokens(["Short."])

        let result = await CompactionService.compact(
            messages: [ChatMessage(role: "user", content: "Hi")],
            baseURL: dummyURL,
            providerID: dummyProviderID,
            model: dummyModel,
            chatService: fake
        )

        #expect(result == nil)
    }

    @Test func compactReturnsNilOnStreamError() async {
        let fake = FakeChatService()
        fake.enqueueTokenError(NSError(domain: "test", code: 1))

        let result = await CompactionService.compact(
            messages: [ChatMessage(role: "user", content: "Hello")],
            baseURL: dummyURL,
            providerID: dummyProviderID,
            model: dummyModel,
            chatService: fake
        )

        #expect(result == nil)
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
