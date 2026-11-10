@testable import Eigin
import Foundation
import Testing

@Suite("Reasoning history compaction")
struct ReasoningHistoryCompactionTests {
    @Test func retainedHistoryIsBudgetedAndNeverPartiallyTruncated() {
        let origin = ReasoningOrigin(
            providerID: UUID(),
            endpoint: "https://api.mistral.ai/v1",
            model: "mistral-large-4-0"
        )
        let history = ReasoningHistory(
            origin: origin, format: "test-reasoning-v1", payload: Data("opaque state".utf8),
            visibleText: "Answer", additionalInputTokens: 600
        )
        let message = ChatMessage(
            role: "assistant",
            content: "Answer",
            reasoningHistory: history
        )
        let plain = message.reasoningScoped(to: nil)
        #expect(TokenEstimator.estimate(messages: [message]) > TokenEstimator
            .estimate(messages: [plain]) + 400)
        let retained = CompactionService.retainedTail(
            messages: [ChatMessage(role: "user", content: "Hi"), message],
            tokenBudget: 2000
        )
        #expect(retained.last?.reasoningHistory == history)
        #expect(CompactionService.truncateForBudget(messages: [message], tokenBudget: 40).isEmpty)
        var edited = message
        edited.content = "Changed answer"
        #expect(TokenEstimator.estimate(messages: [edited]) == TokenEstimator.estimate(
            messages: [edited.reasoningScoped(to: nil)]
        ))
        #expect(edited.reasoningScoped(to: origin).reasoningHistory == nil)
        #expect(message.reasoningScoped(to: origin).reasoningHistory == history)
        edited.content = String(repeating: "x", count: 4000)
        #expect(CompactionService.truncateForBudget(messages: [edited], tokenBudget: 40).isEmpty)
    }
}
