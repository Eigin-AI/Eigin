@testable import Eigin
import Factory
import Foundation
import SwiftData
import Testing

@Suite("AgenticChatLoop", .serialized)
struct AgenticChatLoopTests {
    @MainActor
    private func makeTestContext() throws -> (Agent, Provider, ModelContainer) {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Schema(SchemaV1.models, version: SchemaV1.versionIdentifier),
            configurations: config
        )
        let provider = Provider(name: "Test", baseURL: "https://fake.local")
        container.mainContext.insert(provider)

        let agent = Agent(name: "TestAgent", providerID: provider.id, model: "test-model")
        agent.identityCore = "I am a test agent."
        agent.userCore = "The user is a tester."
        agent.soulCore = ""
        container.mainContext.insert(agent)

        return (agent, provider, container)
    }

    @MainActor private var toolDefinitions: [ToolDefinition] {
        Container.shared.knowledgeService.register { PreviewKnowledgeService() }
        Container.shared.intentService.register { PreviewIntentService() }
        return ToolRegistry.chat(
            permissionPolicy: AlwaysAllowPolicy()
        ).definitions
    }

    @Test @MainActor func contentOnlyResponseReturnsSingleMessage() async throws {
        let (agent, provider, _container) = try makeTestContext()
        _ = _container
        let fakeChatService = FakeChatService()
        let fakeToolExecutor = FakeToolExecutor()

        fakeChatService.enqueueEventStream([
            .contentDelta("Hello "),
            .contentDelta("world!"),
            .finished(.stop),
        ])

        let loop = AgenticChatLoop(isBootstrap: false)
        let messages = [ChatMessage(role: "user", content: "Hi")]

        let produced = try await loop.run(
            messages: messages,
            tools: nil,
            agent: agent,
            provider: provider,
            chatService: fakeChatService,
            toolExecutor: fakeToolExecutor
        )

        #expect(produced.count == 1)
        #expect(produced[0].role == "assistant")
        #expect(produced[0].content == "Hello world!")
    }

    @Test @MainActor func toolCallResponseProducesFullMessageChain() async throws {
        let (agent, provider, _container) = try makeTestContext()
        _ = _container
        let fakeChatService = FakeChatService()
        let fakeToolExecutor = FakeToolExecutor()

        let toolCall = ToolCall(
            id: "call_1", type: "function",
            function: .init(name: "read_core", arguments: "{\"core\":\"identity\"}")
        )

        // Round 1: tool call
        fakeChatService.enqueueEventStream([
            .toolCall(toolCall),
            .finished(.toolCalls),
        ])

        // Round 2: final content
        fakeChatService.enqueueEventStream([
            .contentDelta("Got it!"),
            .finished(.stop),
        ])

        fakeToolExecutor.setResult(for: "call_1", content: "{\"result\":\"I am a test agent.\"}")

        let loop = AgenticChatLoop(isBootstrap: false)
        let messages = [ChatMessage(role: "user", content: "Read my identity")]

        let produced = try await loop.run(
            messages: messages,
            tools: toolDefinitions,
            agent: agent,
            provider: provider,
            chatService: fakeChatService,
            toolExecutor: fakeToolExecutor
        )

        // Should have: assistant (with tool calls) + tool result + final assistant
        #expect(produced.count == 3)
        #expect(produced[0].role == "assistant")
        #expect(produced[0].toolCalls?.count == 1)
        #expect(produced[1].role == "tool")
        #expect(produced[1].toolCallID == "call_1")
        #expect(produced[2].role == "assistant")
        #expect(produced[2].content == "Got it!")
    }

    @Test @MainActor func multipleToolCallsExecutedSequentially() async throws {
        let (agent, provider, _container) = try makeTestContext()
        _ = _container
        let fakeChatService = FakeChatService()
        let fakeToolExecutor = FakeToolExecutor()

        let call1 = ToolCall(
            id: "call_1",
            type: "function",
            function: .init(name: "read_core", arguments: "{\"core\":\"identity\"}")
        )
        let call2 = ToolCall(
            id: "call_2",
            type: "function",
            function: .init(name: "set_presentation", arguments: "{\"emoji\":\"🧪\"}")
        )

        fakeChatService.enqueueEventStream([
            .toolCall(call1),
            .toolCall(call2),
            .finished(.toolCalls),
        ])
        fakeChatService.enqueueEventStream([
            .contentDelta("Done!"),
            .finished(.stop),
        ])

        fakeToolExecutor.setResult(for: "call_1", content: "{\"result\":\"identity content\"}")
        fakeToolExecutor.setResult(for: "call_2", content: "{\"result\":\"OK\"}")

        let loop = AgenticChatLoop(isBootstrap: false)
        let produced = try await loop.run(
            messages: [ChatMessage(role: "user", content: "Setup")],
            tools: toolDefinitions,
            agent: agent,
            provider: provider,
            chatService: fakeChatService,
            toolExecutor: fakeToolExecutor
        )

        // assistant (2 tool calls) + 2 tool results + final assistant = 4
        #expect(produced.count == 4)
        #expect(fakeToolExecutor.calls.count == 2)
    }

    @Test @MainActor func toolCallWithErrorResultContinues() async throws {
        let (agent, provider, _container) = try makeTestContext()
        _ = _container
        let fakeChatService = FakeChatService()
        let fakeToolExecutor = FakeToolExecutor()

        let toolCall = ToolCall(
            id: "call_err", type: "function",
            function: .init(name: "read_core", arguments: "{\"core\":\"bad\"}")
        )

        fakeChatService.enqueueEventStream([
            .toolCall(toolCall),
            .finished(.toolCalls),
        ])
        fakeChatService.enqueueEventStream([
            .contentDelta("I see there was an error."),
            .finished(.stop),
        ])

        fakeToolExecutor.setResult(
            for: "call_err",
            content: "{\"error\":\"Unknown core\"}",
            isError: true
        )

        let loop = AgenticChatLoop(isBootstrap: false)
        let produced = try await loop.run(
            messages: [ChatMessage(role: "user", content: "Read bad core")],
            tools: toolDefinitions,
            agent: agent,
            provider: provider,
            chatService: fakeChatService,
            toolExecutor: fakeToolExecutor
        )

        #expect(produced.count == 3)
        #expect(produced[2].content == "I see there was an error.")
    }
}
