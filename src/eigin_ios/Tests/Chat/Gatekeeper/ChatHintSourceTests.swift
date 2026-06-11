@testable import Eigin
import Foundation
import Testing

@Suite("ChatHintSource")
@MainActor
struct ChatHintSourceTests {
    private func input(
        agentID: UUID = UUID(),
        hasAssistant: Bool = true,
        needsCompaction: Bool = true
    ) -> SystemHintInput {
        var messages = [ChatMessage(role: "user", content: "Hi")]
        if hasAssistant {
            messages.append(ChatMessage(role: "assistant", content: "Hello!"))
        }
        return SystemHintInput(
            agentID: agentID,
            bootstrapComplete: true,
            needsCompaction: needsCompaction,
            hasSpaces: true, // suppress the capability-spaces hint
            messages: messages,
            space: nil,
            spaceID: nil,
            language: nil,
            mode: .text,
            activeIntents: [],
            activeSkills: [],
            availableSkills: [],
            provider: ProviderSnapshot(name: "Test", baseURL: "https://test.com"),
            modelID: "test-model",
            isSmallContext: false
        )
    }

    @Test func nonReactiveFiresWhenConditionMet() async {
        // Non-reactive + a fresh agent ID (no prior delivery history) + compaction
        // needed should always fire the compaction warning (priority 10, cooldown 0).
        let source = ChatHintSource(proactivity: .balanced)
        let result = await source.render(input(agentID: UUID()))
        #expect(result != nil)
        #expect(result?.contains("summarised soon") == true)
    }

    @Test func proactiveFiresJustLikeBalanced() async {
        let source = ChatHintSource(proactivity: .proactive)
        let result = await source.render(input(agentID: UUID()))
        #expect(result != nil)
    }

    @Test func title() {
        #expect(ChatHintSource(proactivity: .reactive).title == "Hint")
    }
}
