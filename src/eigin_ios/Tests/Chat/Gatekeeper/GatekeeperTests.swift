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
            activeSkills: [],
            availableSkills: availableSkills,
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
        let block = await gatekeeper.beforeTurn(input(mode: .liveCall)) ?? ""
        #expect(block.contains("## Interaction mode"))
        #expect(block.contains(InteractionMode.liveCall.fullDescription))
    }

    @Test func secondTurnSameModeEmitsShortReminder() async {
        let gatekeeper = makeGatekeeper(proactivity: .reactive)
        _ = await gatekeeper.beforeTurn(input(mode: .text))
        let second = await gatekeeper.beforeTurn(input(mode: .text)) ?? ""
        #expect(second.contains(InteractionMode.text.shortReminder))
        #expect(!second.contains(InteractionMode.text.fullDescription))
    }

    @Test func modeSwitchReEmitsFullDescription() async {
        let gatekeeper = makeGatekeeper(proactivity: .reactive)
        _ = await gatekeeper.beforeTurn(input(mode: .text))
        _ = await gatekeeper.beforeTurn(input(mode: .text))
        let afterSwitch = await gatekeeper.beforeTurn(input(mode: .liveCall)) ?? ""
        #expect(afterSwitch.contains(InteractionMode.liveCall.fullDescription))
    }

    @Test func minimalBlockWhenMostSourcesSilent() async {
        // Reactive → no hint; no intents, skills, space, language. Only
        // general info (ambient time) and interaction mode render on the
        // first turn. The knowledge source is silent because there's no
        // user message in the input.
        let gatekeeper = makeGatekeeper(proactivity: .reactive)
        let block = await gatekeeper.beforeTurn(input()) ?? ""
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
        )) ?? ""

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
            provider: ProviderSnapshot(name: "Test", baseURL: "https://test.com"),
            modelID: "test-model",
            isSmallContext: true
        )
        let block = await gatekeeper.beforeTurn(inputWithLanguage) ?? ""
        #expect(block.contains("## Language"))
    }

    // MARK: - After turn

    @Test func afterTurnIsNoOp() async {
        let gatekeeper = makeGatekeeper(proactivity: .reactive)
        // Should not throw, mutate anything observable, or crash.
        gatekeeper.afterTurn([ChatMessage(role: "assistant", content: "hi")])
        // Subsequent beforeTurn still works.
        let block = await gatekeeper.beforeTurn(input()) ?? ""
        #expect(block.contains("## Interaction mode"))
    }
}
