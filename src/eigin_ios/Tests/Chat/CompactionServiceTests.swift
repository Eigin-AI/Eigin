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
