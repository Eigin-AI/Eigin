@testable import Eigin
import Foundation
import SwiftData
import Testing

@Suite("Flow tools", .serialized)
struct FlowToolTests {
    // MARK: - Helpers

    @MainActor
    private func makeFixture() throws -> (Agent, Chat, ModelContainer) {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Schema(SchemaV3.models, version: SchemaV3.versionIdentifier),
            configurations: config
        )
        let agent = Agent(name: "TestAgent", providerID: UUID(), model: "test-model")
        container.mainContext.insert(agent)
        let chat = Chat(agentID: agent.id)
        container.mainContext.insert(chat)
        return (agent, chat, container)
    }

    private func makeCall(name: String, arguments: String = "{}") -> ToolCall {
        ToolCall(
            id: "call_\(name)_\(UUID().uuidString)",
            type: "function",
            function: .init(name: name, arguments: arguments)
        )
    }

    // MARK: - start_flow

    @Test @MainActor func startFlowActivatesOwningSkillAndSetsStageZero() async throws {
        let (agent, chat, container) = try makeFixture()
        _ = container // keep the container alive for the duration of the test
        let tool = StartFlowTool(chatID: chat.id)

        let result = await tool.execute(
            makeCall(name: "start_flow", arguments: #"{"flow": "trip"}"#),
            agent: agent
        )

        #expect(!result.isError)
        #expect(chat.isSkillActive("planning"))
        #expect(chat.activeFlow?.flowID == "trip")
        #expect(chat.activeFlow?.stage == 0)
        #expect(chat.activeFlow?.notes.isEmpty == true)
        #expect(result.content.contains("preferences"))
    }

    @Test @MainActor func startFlowDoesNotDuplicateActivationIfAlreadyActive() async throws {
        let (agent, chat, container) = try makeFixture()
        _ = container // keep the container alive for the duration of the test
        chat.activeSkillEntries.append(
            ActiveSkillEntry(
                skillID: "planning",
                activatedAt: .now,
                activatingToolCallID: "earlier"
            )
        )
        let tool = StartFlowTool(chatID: chat.id)

        _ = await tool.execute(
            makeCall(name: "start_flow", arguments: #"{"flow": "trip"}"#),
            agent: agent
        )

        #expect(chat.activeSkillEntries.count == 1)
    }

    @Test @MainActor func startFlowOverwritesExistingActiveFlow() async throws {
        let (agent, chat, container) = try makeFixture()
        _ = container // keep the container alive for the duration of the test
        let tool = StartFlowTool(chatID: chat.id)

        _ = await tool.execute(
            makeCall(name: "start_flow", arguments: #"{"flow": "trip"}"#),
            agent: agent
        )
        let advance = AdvanceFlowTool(chatID: chat.id)
        _ = await advance.execute(
            makeCall(name: "advance_flow", arguments: #"{"notes": "learned something"}"#),
            agent: agent
        )
        #expect(chat.activeFlow?.stage == 1)

        _ = await tool.execute(
            makeCall(name: "start_flow", arguments: #"{"flow": "trip"}"#),
            agent: agent
        )

        #expect(chat.activeFlow?.stage == 0)
        #expect(chat.activeFlow?.notes.isEmpty == true)
    }

    @Test @MainActor func startFlowRejectsUnknownFlow() async throws {
        let (agent, chat, container) = try makeFixture()
        _ = container // keep the container alive for the duration of the test
        let tool = StartFlowTool(chatID: chat.id)

        let result = await tool.execute(
            makeCall(name: "start_flow", arguments: #"{"flow": "not_a_real_flow"}"#),
            agent: agent
        )

        #expect(result.isError)
        #expect(chat.activeFlow == nil)
    }

    // MARK: - advance_flow

    @Test @MainActor func advanceFlowIncrementsStageAndAppendsNotes() async throws {
        let (agent, chat, container) = try makeFixture()
        _ = container // keep the container alive for the duration of the test
        let start = StartFlowTool(chatID: chat.id)
        _ = await start.execute(
            makeCall(name: "start_flow", arguments: #"{"flow": "trip"}"#),
            agent: agent
        )

        let advance = AdvanceFlowTool(chatID: chat.id)
        let result = await advance.execute(
            makeCall(name: "advance_flow", arguments: #"{"notes": "group is a family of four"}"#),
            agent: agent
        )

        #expect(!result.isError)
        #expect(chat.activeFlow?.stage == 1)
        #expect(chat.activeFlow?.notes == ["group is a family of four"])
        #expect(result.content.contains("constraints"))
    }

    @Test @MainActor func advanceFlowRendersAccumulatedNotesWhenStageShowsThem() async throws {
        let (agent, chat, container) = try makeFixture()
        _ = container // keep the container alive for the duration of the test
        let start = StartFlowTool(chatID: chat.id)
        _ = await start.execute(
            makeCall(name: "start_flow", arguments: #"{"flow": "trip"}"#),
            agent: agent
        )

        let advance = AdvanceFlowTool(chatID: chat.id)
        // preferences -> constraints -> options -> logistics
        _ = await advance.execute(
            makeCall(name: "advance_flow", arguments: #"{"notes": "family of four, Berlin"}"#),
            agent: agent
        )
        _ = await advance.execute(
            makeCall(name: "advance_flow", arguments: #"{"notes": "chose the aquarium"}"#),
            agent: agent
        )
        _ = await advance.execute(
            makeCall(name: "advance_flow", arguments: #"{"notes": "booked the hotel"}"#),
            agent: agent
        )
        // logistics -> itinerary (show_notes = true)
        let result = await advance.execute(makeCall(name: "advance_flow"), agent: agent)

        #expect(!result.isError)
        #expect(chat.activeFlow?.stage == 4)
        #expect(result.content.contains("family of four, Berlin"))
        #expect(result.content.contains("chose the aquarium"))
        #expect(result.content.contains("booked the hotel"))
    }

    @Test @MainActor func advanceFlowErrorsWithNoActiveFlow() async throws {
        let (agent, chat, container) = try makeFixture()
        _ = container // keep the container alive for the duration of the test
        let tool = AdvanceFlowTool(chatID: chat.id)

        let result = await tool.execute(makeCall(name: "advance_flow"), agent: agent)

        #expect(result.isError)
        #expect(result.content.contains("start_flow"))
    }

    @Test @MainActor func advanceFlowClosesAfterLastStage() async throws {
        let (agent, chat, container) = try makeFixture()
        _ = container // keep the container alive for the duration of the test
        let start = StartFlowTool(chatID: chat.id)
        _ = await start.execute(
            makeCall(name: "start_flow", arguments: #"{"flow": "trip"}"#),
            agent: agent
        )

        let advance = AdvanceFlowTool(chatID: chat.id)
        var lastResult: ToolResult?
        // preferences(0) -> constraints(1) -> options(2) -> logistics(3) -> itinerary(4) ->
        // complete
        for _ in 0 ..< 5 {
            lastResult = await advance.execute(makeCall(name: "advance_flow"), agent: agent)
        }

        #expect(lastResult?.isError == false)
        #expect(chat.activeFlow == nil)
        #expect(lastResult?.content.contains("complete") == true)
    }
}
