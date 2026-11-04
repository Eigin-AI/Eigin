@testable import Eigin
import Foundation
import Testing

@Suite("Bounded preparation previews")
@MainActor
struct PreparationPreviewTests {
    @Test func backgroundLevelsShareInstructionsWhileModesStayDistinct() {
        let agent = Agent(name: "Test", providerID: UUID(), model: "test")
        for mode in BackgroundRunMode.allCases {
            let balanced = BackgroundPrompt.build(agent: agent, proactivity: .balanced, mode: mode)
            let proactive = BackgroundPrompt.build(
                agent: agent,
                proactivity: .proactive,
                mode: mode
            )
            #expect(balanced == proactive)
            #expect(balanced.components(separatedBy: "You have a moment to yourself.").count == 2)
            if mode == .preparation {
                #expect(balanced.contains("Save findings as you go with save_preparation"))
                #expect(!balanced.contains("background_notify"))
            } else {
                #expect(balanced.contains("tidy the knowledge"))
                #expect(balanced.contains("background_notify"))
            }
        }
        let reactive = BackgroundPrompt.build(agent: agent, proactivity: .reactive)
        #expect(reactive.contains("don't do anything the user didn't ask for"))
    }

    @Test func largeGoalsAndTaskCollectionsShareABoundedPreview() {
        let agent = Agent(name: "Test", providerID: UUID(), model: "test")
        let intents = (0 ..< 100).map { index in
            IntentSnapshot(
                id: UUID(),
                content: "Ranked goal \(index) " + String(repeating: "detail ", count: 200),
                status: .active,
                tasks: (0 ..< 500).map { IntentTask(content: "Task \($0) " + String(
                    repeating: "work ",
                    count: 100
                )) },
                events: [],
                schedules: [],
                createdAt: .now,
                updatedAt: .now
            )
        }
        let upcoming = (0 ..< 100).map { "Upcoming initiative \($0) " + String(
            repeating: "instructions ",
            count: 100
        ) }
        let base = BackgroundPrompt.build(agent: agent, proactivity: .balanced, mode: .preparation)
        let prompt = BackgroundPrompt.build(
            agent: agent,
            proactivity: .balanced,
            activeIntents: intents,
            mode: .preparation,
            upcomingInitiatives: upcoming
        )
        #expect(prompt.count - base.count <= PreparationPreview.maxCharacters)
        #expect(prompt.contains("Ranked goal 0"))
        #expect(prompt.contains("Upcoming initiative 0"))
        #expect(prompt.contains("open tasks"))
        #expect(prompt.contains("omitted"))
        #expect(!prompt.contains("Task 499"))
        #expect(!prompt.contains("Upcoming initiative 99"))
    }
}
