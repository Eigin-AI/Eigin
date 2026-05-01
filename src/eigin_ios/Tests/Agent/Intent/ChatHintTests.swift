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
            needsCompaction: false
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
            needsCompaction: false
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
            needsCompaction: true // forces compaction warning which has no cooldown
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
            needsCompaction: true
        )
        // Compaction warning has highest priority and no cooldown
        #expect(result != nil)
        #expect(result?.contains("summarised soon") == true)
    }
}
