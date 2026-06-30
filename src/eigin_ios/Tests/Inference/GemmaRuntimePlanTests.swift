@testable import Eigin
import Testing

/// Verifies the prefix-diff that decides whether ``GemmaRuntime`` reuses the
/// live LiteRT conversation (prefix cache) or rebuilds it on divergence.
@Suite("GemmaRuntime prefix diff")
struct GemmaRuntimePlanTests {
    typealias Message = GemmaRuntime.Message

    private func system(_ s: String) -> Message {
        .init(role: .system, content: s)
    }

    private func user(_ s: String) -> Message {
        .init(role: .user, content: s)
    }

    private func assistant(_ s: String) -> Message {
        .init(role: .assistant, content: s)
    }

    @Test func firstTurnRebuildsAndKeepsSystemOutOfPrompt() {
        let messages = [system("You are helpful."), user("Hi")]
        let decision = GemmaRuntime.planDecision(
            messages: messages, ingested: [], hasConversation: false
        )
        #expect(decision.mode == .rebuild)
        #expect(decision.priorTurns == [system("You are helpful.")])
        #expect(decision.pendingTurns == [user("Hi")])
        #expect(decision.promptText == "Hi")
    }

    @Test func appendReusesWhenLiveConversationHoldsPrior() {
        let prior = [system("S"), user("Q1"), assistant("A1")]
        let messages = prior + [user("Q2")]
        let decision = GemmaRuntime.planDecision(
            messages: messages, ingested: prior, hasConversation: true
        )
        #expect(decision.mode == .reuse)
        #expect(decision.pendingTurns == [user("Q2")])
        #expect(decision.promptText == "Q2")
    }

    @Test func editedHistoryForcesRebuild() {
        let ingested = [system("S"), user("Q1"), assistant("A1")]
        // The user edited Q1, so the prior turns no longer match what's cached.
        let messages = [system("S"), user("Q1-edited"), assistant("A1"), user("Q2")]
        let decision = GemmaRuntime.planDecision(
            messages: messages, ingested: ingested, hasConversation: true
        )
        #expect(decision.mode == .rebuild)
    }

    @Test func noLiveConversationForcesRebuildEvenWhenPriorMatches() {
        let prior = [system("S"), user("Q1"), assistant("A1")]
        let messages = prior + [user("Q2")]
        let decision = GemmaRuntime.planDecision(
            messages: messages, ingested: prior, hasConversation: false
        )
        #expect(decision.mode == .rebuild)
    }

    @Test func trailingUserAndToolTurnsAreCombinedIntoPrompt() {
        let messages = [
            system("S"), user("Q1"), assistant("A1"),
            user("call a tool"), user("[tool result]: 42"),
        ]
        let decision = GemmaRuntime.planDecision(
            messages: messages,
            ingested: [system("S"), user("Q1"), assistant("A1")],
            hasConversation: true
        )
        #expect(decision.mode == .reuse)
        #expect(decision.pendingTurns.count == 2)
        #expect(decision.promptText == "call a tool\n\n[tool result]: 42")
    }

    // MARK: - Context overflow truncation

    @Test func dropOldestTurnRemovesFirstUserAssistantPair() {
        let messages = [
            system("S"), user("Q1"), assistant("A1"), user("Q2"), assistant("A2"), user("Q3"),
        ]
        let result = GemmaRuntime.dropOldestTurn(messages)
        #expect(result == [system("S"), user("Q2"), assistant("A2"), user("Q3")])
    }

    @Test func dropOldestTurnRemovesOrphanUserWithNoAssistantFollow() {
        // user("Q1") is immediately followed by another user turn, not an assistant.
        let messages = [system("S"), user("Q1"), user("Q2"), assistant("A2"), user("Q3")]
        let result = GemmaRuntime.dropOldestTurn(messages)
        #expect(result == [system("S"), user("Q2"), assistant("A2"), user("Q3")])
    }

    @Test func dropOldestTurnReturnsNilWhenOnlyLastUserRemains() {
        // Only a pending user turn — nothing to drop.
        let messages = [system("S"), user("Q1")]
        #expect(GemmaRuntime.dropOldestTurn(messages) == nil)
    }

    @Test func dropOldestTurnReturnsNilForSingleUserMessage() {
        #expect(GemmaRuntime.dropOldestTurn([user("Hi")]) == nil)
    }
}
