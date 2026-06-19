@testable import Eigin
import Factory
import Foundation
import SwiftData
import Testing

@Suite("ToolExecutor", .serialized)
struct ToolExecutorTests {
    init() {
        Container.shared.reset()
        Container.shared.knowledgeService.register { PreviewKnowledgeService() }
        Container.shared.intentService.register { PreviewIntentService() }
    }

    @MainActor
    private func makeExecutor() -> ToolRegistry {
        ToolRegistry.chat(permissionPolicy: AlwaysAllowPolicy())
    }

    @MainActor
    private func makeAgent() throws -> (Agent, ModelContainer) {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Schema(SchemaV1.models, version: SchemaV1.versionIdentifier),
            configurations: config
        )
        let agent = Agent(name: "TestAgent", providerID: UUID(), model: "test-model")
        agent.identityCore = "I am a test agent."
        agent.userCore = "The user is a tester."
        agent.soulCore = "I exist to help."
        container.mainContext.insert(agent)
        return (agent, container)
    }

    private func makeCall(name: String, arguments: String) -> ToolCall {
        ToolCall(
            id: "call_\(name)",
            type: "function",
            function: .init(name: name, arguments: arguments)
        )
    }

    // MARK: - read_core

    @Test @MainActor func readCoreReturnsIdentity() async throws {
        let (agent, _container) = try makeAgent()
        _ = _container
        let call = makeCall(name: "read_core", arguments: "{\"core\":\"identity\"}")
        let result = await makeExecutor().execute(call, agent: agent)

        #expect(!result.isError)
        #expect(result.content.contains("test agent"))
    }

    @Test @MainActor func readCoreReturnsUser() async throws {
        let (agent, _container) = try makeAgent()
        _ = _container
        let call = makeCall(name: "read_core", arguments: "{\"core\":\"user\"}")
        let result = await makeExecutor().execute(call, agent: agent)

        #expect(!result.isError)
        #expect(result.content.contains("tester"))
    }

    @Test @MainActor func readCoreReturnsSoul() async throws {
        let (agent, _container) = try makeAgent()
        _ = _container
        let call = makeCall(name: "read_core", arguments: "{\"core\":\"soul\"}")
        let result = await makeExecutor().execute(call, agent: agent)

        #expect(!result.isError)
        #expect(result.content.contains("help"))
    }

    @Test @MainActor func readCoreErrorForUnknown() async throws {
        let (agent, _container) = try makeAgent()
        _ = _container
        let call = makeCall(name: "read_core", arguments: "{\"core\":\"unknown\"}")
        let result = await makeExecutor().execute(call, agent: agent)

        #expect(result.isError)
        #expect(result.content.contains("Unknown core"))
    }

    // MARK: - edit_core

    @Test @MainActor func editCoreReplacesString() async throws {
        let (agent, _container) = try makeAgent()
        _ = _container
        let call = makeCall(
            name: "edit_core",
            arguments: "{\"core\":\"identity\",\"old_string\":\"test agent\",\"new_string\":\"amazing agent\"}"
        )
        let result = await makeExecutor().execute(call, agent: agent)

        #expect(!result.isError)
        #expect(agent.identityCore == "I am a amazing agent.")
    }

    @Test @MainActor func editCoreRejectsEmptyOldString() async throws {
        let (agent, _container) = try makeAgent()
        _ = _container
        let call = makeCall(
            name: "edit_core",
            arguments: "{\"core\":\"identity\",\"old_string\":\"\",\"new_string\":\" And I'm great.\"}"
        )
        let result = await makeExecutor().execute(call, agent: agent)

        #expect(result.isError)
        #expect(agent.identityCore == "I am a test agent.")
    }

    @Test @MainActor func editCorePopulatesEmptyCore() async throws {
        let (agent, _container) = try makeAgent()
        _ = _container
        agent.userCore = ""
        let call = makeCall(
            name: "edit_core",
            arguments: "{\"core\":\"user\",\"old_string\":\"\",\"new_string\":\"They are a designer.\"}"
        )
        let result = await makeExecutor().execute(call, agent: agent)

        #expect(!result.isError)
        #expect(agent.userCore == "They are a designer.")
    }

    @Test @MainActor func editCorePopulatesWhitespaceOnlyCore() async throws {
        let (agent, _container) = try makeAgent()
        _ = _container
        agent.userCore = "  \n  "
        let call = makeCall(
            name: "edit_core",
            arguments: "{\"core\":\"user\",\"old_string\":\"\",\"new_string\":\"They are a designer.\"}"
        )
        let result = await makeExecutor().execute(call, agent: agent)

        #expect(!result.isError)
        #expect(agent.userCore == "They are a designer.")
    }

    @Test @MainActor func editCoreErrorWhenNotFound() async throws {
        let (agent, _container) = try makeAgent()
        _ = _container
        let call = makeCall(
            name: "edit_core",
            arguments: "{\"core\":\"identity\",\"old_string\":\"nonexistent\",\"new_string\":\"replacement\"}"
        )
        let result = await makeExecutor().execute(call, agent: agent)

        #expect(result.isError)
        #expect(result.content.contains("not found"))
    }

    @Test @MainActor func editCoreWarnsOnMultipleMatches() async throws {
        let (agent, _container) = try makeAgent()
        _ = _container
        agent.identityCore = "test test test"
        let call = makeCall(
            name: "edit_core",
            arguments: "{\"core\":\"identity\",\"old_string\":\"test\",\"new_string\":\"PASS\"}"
        )
        let result = await makeExecutor().execute(call, agent: agent)

        #expect(!result.isError)
        #expect(result.content.contains("warnings"))
        #expect(result.content.contains("replaced only the first"))
        #expect(agent.identityCore == "PASS test test")
    }

    // MARK: - set_presentation

    @Test @MainActor func setPresentationUpdatesNameAndEmoji() async throws {
        let (agent, _container) = try makeAgent()
        _ = _container
        let call = makeCall(
            name: "set_presentation",
            arguments: "{\"name\":\"NewName\",\"emoji\":\"🎉\"}"
        )
        let result = await makeExecutor().execute(call, agent: agent)

        #expect(!result.isError)
        #expect(agent.name == "NewName")
        #expect(agent.emoji == "🎉")
    }

    // MARK: - Unknown tool

    @Test @MainActor func unknownToolReturnsError() async throws {
        let (agent, _container) = try makeAgent()
        _ = _container
        let call = makeCall(name: "nonexistent_tool", arguments: "{}")
        let result = await makeExecutor().execute(call, agent: agent)

        #expect(result.isError)
        #expect(result.content.contains("Unknown tool"))
    }
}
