@testable import Eigin
import Foundation
import Testing

@Suite("InteractionModeSource")
@MainActor
struct InteractionModeSourceTests {
    private func input(mode: InteractionMode, compact: Bool = false) -> SystemHintInput {
        SystemHintInput(
            agentID: UUID(),
            bootstrapComplete: true,
            needsCompaction: false,
            hasSpaces: false,
            messages: [],
            space: nil,
            spaceID: nil,
            language: nil,
            mode: mode,
            activeIntents: [],
            activeSkills: [],
            availableSkills: [],
            provider: ProviderSnapshot(name: "Test", baseURL: "https://test.com"),
            modelID: "test-model",
            isSmallContext: compact
        )
    }

    @Test func firstRenderEmitsFullDescription() async {
        let source = InteractionModeSource()
        let result = await source.render(input(mode: .liveCall))
        #expect(result == InteractionMode.liveCall.fullDescription)
    }

    @Test func secondRenderWithSameModeEmitsShortReminder() async {
        let source = InteractionModeSource()
        _ = await source.render(input(mode: .text))
        let second = await source.render(input(mode: .text))
        #expect(second == InteractionMode.text.shortReminder)
    }

    @Test func modeChangeReEmitsFullDescription() async {
        let source = InteractionModeSource()
        _ = await source.render(input(mode: .text))
        _ = await source.render(input(mode: .text))
        let afterSwitch = await source.render(input(mode: .liveCall))
        #expect(afterSwitch == InteractionMode.liveCall.fullDescription)
    }

    @Test func switchingBackAndForthAlwaysRendersFullOnChange() async {
        let source = InteractionModeSource()
        #expect(await source.render(input(mode: .text)) == InteractionMode.text.fullDescription)
        #expect(await source.render(input(mode: .dictation)) == InteractionMode.dictation
            .fullDescription)
        #expect(await source.render(input(mode: .dictation)) == InteractionMode.dictation
            .shortReminder)
        #expect(await source.render(input(mode: .liveCall)) == InteractionMode.liveCall
            .fullDescription)
        #expect(await source.render(input(mode: .text)) == InteractionMode.text.fullDescription)
    }

    @Test func title() {
        #expect(InteractionModeSource().title == "Interaction mode")
    }
}
