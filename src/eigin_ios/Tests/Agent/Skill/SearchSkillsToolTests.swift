@testable import Eigin
import Foundation
import Testing

@Suite("SearchSkillsTool")
@MainActor
struct SearchSkillsToolTests {
    private func makeCall(arguments: String) -> ToolCall {
        ToolCall(
            id: "call_search_\(UUID().uuidString)",
            type: "function",
            function: .init(name: "search_skills", arguments: arguments)
        )
    }

    private func makeAgent() -> Agent {
        Agent(name: "TestAgent", providerID: UUID(), model: "test-model")
    }

    @Test func definitionNamesQueryAndPointsAtActivation() {
        let definition = SearchSkillsTool().definition()
        #expect(definition.function.name == "search_skills")
        #expect(definition.function.description.contains("activate_skill"))
    }

    @Test func missingQueryErrors() async {
        let tool = SearchSkillsTool(skillIndex: SkillIndex(embed: { _ in [1.0] }))
        let result = await tool.execute(makeCall(arguments: "{}"), agent: makeAgent())
        #expect(result.isError)
    }

    @Test func returnsMatchingSkill_whenHintsMiss() async {
        // Cooking's descriptor mentions recipes; the fake embedder keys on
        // "recipe", so only cooking scores above threshold.
        let index = SkillIndex { text in text.contains("recipe") ? [1.0, 0.0] : [0.0, 1.0] }
        let tool = SearchSkillsTool(skillIndex: index)

        let result = await tool.execute(
            makeCall(arguments: #"{"query": "recipe"}"#),
            agent: makeAgent()
        )
        #expect(!result.isError)
        #expect(result.content.contains("cooking"))
        #expect(!result.content.contains("email"))
    }

    @Test func skillsThatNeedConnectingAreFoundAndSayWhatTheyNeed() async {
        // Nothing connected: email is still found, so the agent can activate it
        // and be asked to connect, and it says what it needs.
        let tool = SearchSkillsTool(skillIndex: SkillIndex(embed: { _ in [1.0] }))
        let result = await tool.execute(
            makeCall(arguments: #"{"query": "send her a message"}"#),
            agent: makeAgent()
        )
        #expect(!result.isError)
        #expect(result.content.contains("email"))
        #expect(result.content.contains("asks the user to connect"))
    }

    @Test func reportsNoMatchesAsSuccess() async {
        // Query embeds to its own vector; no descriptor embeds identically, so
        // everything scores 0 — below threshold.
        let index = SkillIndex { text in text == "abc" ? [1.0, 0.0] : [0.0, 1.0] }
        let tool = SearchSkillsTool(skillIndex: index)
        let result = await tool.execute(
            makeCall(arguments: #"{"query": "abc"}"#),
            agent: makeAgent()
        )
        #expect(!result.isError)
        #expect(result.content.contains("No matching skills"))
    }

    @Test func unavailableEmbedderDoesNotReportANoMatch() async {
        // Embedder can't run: the agent must not conclude no skill exists.
        let tool = SearchSkillsTool(skillIndex: SkillIndex(embed: { _ in nil }))
        let result = await tool.execute(
            makeCall(arguments: #"{"query": "anything"}"#),
            agent: makeAgent()
        )
        #expect(!result.isError)
        #expect(result.content.contains("unavailable"))
        #expect(!result.content.contains("No matching skills"))
    }
}
