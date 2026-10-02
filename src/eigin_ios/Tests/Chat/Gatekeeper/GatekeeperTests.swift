@testable import Eigin
import Foundation
import Testing

@Suite("Gatekeeper")
@MainActor
struct GatekeeperTests {
    private func input(
        mode: InteractionMode = .text,
        activeIntents: [IntentSnapshot] = [],
        availableSkills: [Skill] = [],
        activeSkills: [Skill] = [],
        isSmallContext: Bool = false,
        messages: [ChatMessage] = []
    ) -> SystemHintInput {
        SystemHintInput(
            agentID: UUID(),
            bootstrapComplete: true,
            needsCompaction: false,
            hasSpaces: false,
            messages: messages,
            space: nil,
            spaceID: nil,
            language: nil,
            mode: mode,
            activeIntents: activeIntents,
            activeSkills: activeSkills,
            availableSkills: availableSkills,
            activeFlow: nil,
            provider: ProviderSnapshot(name: "Test", baseURL: "https://test.com"),
            modelID: "test-model",
            isSmallContext: isSmallContext
        )
    }

    private func intent(_ content: String) -> IntentSnapshot {
        IntentSnapshot(
            id: UUID(), content: content, status: .active, tasks: [],
            events: [], schedules: [], createdAt: .now, updatedAt: .now
        )
    }

    private func skill(id: String, displayName: String) -> Skill {
        Skill(
            id: id, displayName: displayName, description: "desc",
            instruction: "do \(id)", requiredTools: [], alwaysActive: false
        )
    }

    private func makeGatekeeper(proactivity: ProactivityLevel) -> Gatekeeper {
        Gatekeeper(proactivity: proactivity, knowledgeService: FakeKnowledgeService())
    }

    // MARK: - Full source list behaviour

    @Test func firstTurnEmitsFullInteractionMode() async {
        let gatekeeper = makeGatekeeper(proactivity: .reactive)
        let block = await gatekeeper.beforeTurn(input(mode: .liveCall)).hint ?? ""
        #expect(block.contains("## Interaction mode"))
        #expect(block.contains(InteractionMode.liveCall.fullDescription))
    }

    @Test func secondTurnSameModeEmitsShortReminder() async {
        let gatekeeper = makeGatekeeper(proactivity: .reactive)
        _ = await gatekeeper.beforeTurn(input(mode: .text))
        let second = await gatekeeper.beforeTurn(input(mode: .text)).hint ?? ""
        #expect(second.contains(InteractionMode.text.shortReminder))
        #expect(!second.contains(InteractionMode.text.fullDescription))
    }

    @Test func modeSwitchReEmitsFullDescription() async {
        let gatekeeper = makeGatekeeper(proactivity: .reactive)
        _ = await gatekeeper.beforeTurn(input(mode: .text))
        _ = await gatekeeper.beforeTurn(input(mode: .text))
        let afterSwitch = await gatekeeper.beforeTurn(input(mode: .liveCall)).hint ?? ""
        #expect(afterSwitch.contains(InteractionMode.liveCall.fullDescription))
    }

    @Test func minimalBlockWhenMostSourcesSilent() async {
        // Reactive → no hint; no intents, skills, space, language. Only
        // general info (ambient time) and interaction mode render on the
        // first turn. The knowledge source is silent because there's no
        // user message in the input.
        let gatekeeper = makeGatekeeper(proactivity: .reactive)
        let block = await gatekeeper.beforeTurn(input()).hint ?? ""
        #expect(block.contains("## General info"))
        #expect(block.contains("## Interaction mode"))
        #expect(!block.contains("## Active intents"))
        #expect(!block.contains("## Available skills"))
        #expect(!block.contains("## Space"))
        #expect(!block.contains("## Language"))
        #expect(!block.contains("## Related knowledge"))
    }

    // MARK: - Compact source list

    @Test func compactBlockOnlyHasGeneralInfo() async {
        let gatekeeper = makeGatekeeper(proactivity: .reactive)
        let block = await gatekeeper.beforeTurn(input(
            mode: .liveCall,
            activeIntents: [intent("Learn Swift")],
            availableSkills: [skill(id: "web", displayName: "Web")],
            isSmallContext: true
        )).hint ?? ""

        // Small-context uses smallSources: GeneralInfo, Language, Space,
        // InteractionMode, ActiveIntents (truncated), RelevantKnowledge.
        #expect(block.contains("## General info"))
        #expect(block.contains("## Interaction mode"))
        // Active intents render in compact mode (truncated, no IDs/tasks).
        #expect(block.contains("## Active intents"))
        // These sources are not in smallSources.
        #expect(!block.contains("## Available skills"))
        #expect(!block.contains("## Active skills"))
        #expect(!block.contains("## Hint"))
    }

    @Test func compactWithLanguageEmitsLanguageSection() async {
        let gatekeeper = makeGatekeeper(proactivity: .proactive)
        let inputWithLanguage = SystemHintInput(
            agentID: UUID(),
            bootstrapComplete: true,
            needsCompaction: false,
            hasSpaces: false,
            messages: [],
            space: nil,
            spaceID: nil,
            language: .english,
            mode: .text,
            activeIntents: [],
            activeSkills: [],
            availableSkills: [],
            activeFlow: nil,
            provider: ProviderSnapshot(name: "Test", baseURL: "https://test.com"),
            modelID: "test-model",
            isSmallContext: true
        )
        let block = await gatekeeper.beforeTurn(inputWithLanguage).hint ?? ""
        #expect(block.contains("## Language"))
    }

    // MARK: - After turn

    @Test func afterTurnIsNoOp() async {
        let gatekeeper = makeGatekeeper(proactivity: .reactive)
        // Should not throw, mutate anything observable, or crash.
        gatekeeper.afterTurn([ChatMessage(role: "assistant", content: "hi")])
        // Subsequent beforeTurn still works.
        let block = await gatekeeper.beforeTurn(input()).hint ?? ""
        #expect(block.contains("## Interaction mode"))
    }

    // MARK: - Skill hints (retrieval, not activation)

    private func userMessage(_ text: String) -> ChatMessage {
        ChatMessage(role: "user", content: text)
    }

    /// Every query and descriptor embeds to the same vector → everything matches.
    private func matchingSkillIndex() -> SkillIndex {
        SkillIndex(embed: { _ in [1.0, 0.0] })
    }

    /// Query embeds to [1, 0], descriptors to [0, 1] → cosine 0, below threshold.
    private func noMatchSkillIndex(query: String) -> SkillIndex {
        SkillIndex(embed: { text in text == query ? [1.0, 0.0] : [0.0, 1.0] })
    }

    private func makeGatekeeper(skillIndex: SkillIndex) -> Gatekeeper {
        Gatekeeper(
            proactivity: .reactive,
            knowledgeService: FakeKnowledgeService(),
            skillIndex: skillIndex
        )
    }

    @Test func hintsMatchedSkillsInsteadOfActivating() async {
        let gatekeeper = makeGatekeeper(skillIndex: matchingSkillIndex())
        let result = await gatekeeper.beforeTurn(input(
            availableSkills: [skill(id: "gitlab", displayName: "GitLab")],
            messages: [userMessage("find this issue on GitLab")]
        ))

        // Skills are hinted, never auto-activated: beforeTurn returns a hint.
        let hint = result.hint ?? ""
        #expect(hint.contains("## Available skills"))
        #expect(hint.contains("gitlab"))
    }

    @Test func noSkillSectionWhenNothingMatchesThreshold() async {
        let gatekeeper = makeGatekeeper(
            skillIndex: noMatchSkillIndex(query: "find this issue on GitLab")
        )
        let result = await gatekeeper.beforeTurn(input(
            availableSkills: [skill(id: "gitlab", displayName: "GitLab")],
            messages: [userMessage("find this issue on GitLab")]
        ))
        #expect(!(result.hint ?? "").contains("## Available skills"))
    }

    @Test func noSkillSectionInSmallContext() async {
        // Small-context models get no skill tools at all — no hints either.
        let gatekeeper = makeGatekeeper(skillIndex: matchingSkillIndex())
        let result = await gatekeeper.beforeTurn(input(
            availableSkills: [skill(id: "gitlab", displayName: "GitLab")],
            isSmallContext: true,
            messages: [userMessage("find this issue on GitLab")]
        ))
        #expect(!(result.hint ?? "").contains("## Available skills"))
    }

    @Test func fallsBackToCappedFullListWhenEmbedderUnavailable() async {
        let gatekeeper = makeGatekeeper(skillIndex: SkillIndex(embed: { _ in nil }))
        let result = await gatekeeper.beforeTurn(input(
            availableSkills: [skill(id: "gitlab", displayName: "GitLab")],
            messages: [userMessage("find this issue on GitLab")]
        ))
        let hint = result.hint ?? ""
        #expect(hint.contains("## Available skills"))
        #expect(hint.contains("GitLab"))
        #expect(hint.contains("search_skills"))
    }
}
