@testable import Eigin
import Foundation
import Testing

@Suite("ChatHint")
struct ChatHintTests {
    private let agentID = UUID()

    // MARK: - evaluate

    @Test func evaluateReturnsNilDuringBootstrap() {
        let result = ChatHint.evaluate(
            agentID: agentID,
            bootstrapComplete: false,
            messages: [
                ChatMessage(role: "user", content: "Hi"),
                ChatMessage(role: "assistant", content: "Hello!"),
            ],
            hasSpaces: false,
            needsCompaction: false,
            initiative: .balanced
        )
        #expect(result == nil)
    }

    @Test func evaluateReturnsNilBeforeFirstAssistantMessage() {
        let result = ChatHint.evaluate(
            agentID: agentID,
            bootstrapComplete: true,
            messages: [
                ChatMessage(role: "user", content: "Hi"),
            ],
            hasSpaces: false,
            needsCompaction: false,
            initiative: .balanced
        )
        #expect(result == nil)
    }

    @Test func evaluateReturnsPlainText() {
        // Use a fresh agent ID to avoid any UserDefaults cooldown from prior runs.
        let result = ChatHint.evaluate(
            agentID: UUID(),
            bootstrapComplete: true,
            messages: [
                ChatMessage(role: "user", content: "Hi"),
                ChatMessage(role: "assistant", content: "Hello!"),
            ],
            hasSpaces: true, // suppress the spaces hint
            needsCompaction: true, // forces compaction warning which has no cooldown
            initiative: .balanced
        )
        #expect(result != nil)
        // The returned text should be a plain-markdown body, no XML wrapper.
        #expect(result?.contains("<chat_hint>") == false)
        #expect(result?.contains("</chat_hint>") == false)
    }

    @Test func evaluateCompactionWarningFiresWhenNeeded() {
        let result = ChatHint.evaluate(
            agentID: UUID(), // fresh agent ID — no cooldown history
            bootstrapComplete: true,
            messages: [
                ChatMessage(role: "user", content: "Hi"),
                ChatMessage(role: "assistant", content: "Hello!"),
            ],
            hasSpaces: true, // has spaces, so spaces hint won't fire
            needsCompaction: true,
            initiative: .balanced
        )
        // Compaction warning has highest priority and no cooldown
        #expect(result != nil)
        #expect(result?.contains("summarised soon") == true)
    }

    // MARK: - introduceInitiative

    /// Fires for a fresh (undecided) reactive agent — this is the
    /// post-onboarding proactivity offer path.
    @Test func introduceInitiativeFiresWhenReactiveAndUndecided() {
        let id = UUID() // fresh — no cooldown history, no decision recorded
        let result = ChatHint.evaluate(
            agentID: id,
            bootstrapComplete: true,
            messages: [
                ChatMessage(role: "user", content: "I keep forgetting to check the news"),
                ChatMessage(role: "assistant", content: "I could keep an eye on that for you."),
            ],
            hasSpaces: true,
            needsCompaction: false,
            initiative: .reactive
        )
        #expect(result?.contains("proactiv") == true)
    }

    /// An explicit choice — any level, including staying reactive — ends
    /// the offers.
    @Test func introduceInitiativeSuppressedOnceDecided() {
        ProactivityDecision.markDecided()
        defer { ProactivityDecision.removeDecision() }

        let result = ChatHint.evaluate(
            agentID: UUID(),
            bootstrapComplete: true,
            messages: [
                ChatMessage(role: "user", content: "Hi"),
                ChatMessage(role: "assistant", content: "Hello!"),
            ],
            hasSpaces: true,
            needsCompaction: false,
            initiative: .reactive
        )
        #expect(result?.contains("proactiv") != true, "hint fires despite decision")
    }

    @Test func introduceInitiativeSuppressedForBackgroundLevels() {
        for level in [ProactivityLevel.balanced, .proactive] {
            let id = UUID() // fresh — undecided, but initiative is on
            let result = ChatHint.evaluate(
                agentID: id,
                bootstrapComplete: true,
                messages: [
                    ChatMessage(role: "user", content: "Hi"),
                    ChatMessage(role: "assistant", content: "Hello!"),
                ],
                hasSpaces: true,
                needsCompaction: false,
                initiative: level
            )
            #expect(result?.contains("proactiv") != true, "hint fired at \(level)")
        }
    }

    /// The initiative offer outranks routine hints so it lands in the first
    /// exchanges after onboarding.
    @Test func introduceInitiativeOutranksRoutineHints() {
        let initiative = HintCatalog.introduceInitiative
        #expect(initiative.priority > HintCatalog.revisitCoreDocs.priority)
        #expect(initiative.priority > HintCatalog.collectKnowledge.priority)
        #expect(initiative.priority < HintCatalog.compactionWarning.priority)
    }

    /// Stays present on every eligible turn within its burst — the right
    /// moment to act on it may arrive several turns after its first
    /// appearance — then goes on cooldown.
    @Test func introduceInitiativeFiresThroughItsBurstThenCoolsDown() {
        let id = UUID() // fresh — no cooldown history, no decision recorded
        defer { ProactivityDecision.removeDecision() }

        func evaluate() -> String? {
            ChatHint.evaluate(
                agentID: id,
                bootstrapComplete: true,
                messages: [
                    ChatMessage(role: "user", content: "Hi"),
                    ChatMessage(role: "assistant", content: "Hello!"),
                ],
                hasSpaces: true,
                needsCompaction: false,
                initiative: .reactive
            )
        }

        let burst = HintCatalog.introduceInitiative.burst
        for turn in 1 ... burst {
            #expect(evaluate()?.contains("proactiv") == true, "expected on burst turn \(turn)")
        }
        #expect(evaluate()?.contains("proactiv") != true, "cooldown after burst")
    }

    /// Hint burst settings: the proactivity offer runs longest — it needs to
    /// be present when a reason to enable it shows up — and the rhythm hints
    /// get shorter windows so they don't dominate a conversation.
    @Test func burstConfiguration() {
        #expect(HintCatalog.introduceInitiative.burst == 8)
        #expect(HintCatalog.collectKnowledge.burst == 4)
        #expect(HintCatalog.revisitCoreDocs.burst == 8)
        #expect(HintCatalog.selfConfigure.burst == 8)
        #expect(HintCatalog.capabilitySpaces.burst == 8)
    }
}
