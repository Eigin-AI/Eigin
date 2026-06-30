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

    @Test @MainActor func recoversWhenSelectedModelIsRetired() async throws {
        let (agent, provider, _container) = try makeTestContext()
        _ = _container
        agent.model = "retired-model"
        provider.availableModels = ["retired-model"]

        let refresher = FakeProviderModelRefresher(modelsToReturn: ["claude-sonnet-4-6"])
        Container.shared.providerModelRefresher.register { refresher }
        defer { Container.shared.providerModelRefresher.reset() }

        let fakeChatService = FakeChatService()
        // First attempt fails because the model no longer exists; the retry succeeds.
        fakeChatService.throwOnEventStream(
            OpenAICompatibleClientError.httpError(
                404, body: "The model `retired-model` does not exist"
            )
        )
        fakeChatService.enqueueEventStream([
            .contentDelta("Recovered!"),
            .finished(.stop),
        ])

        let loop = AgenticChatLoop(isBootstrap: false)
        let produced = try await loop.run(
            messages: [ChatMessage(role: "user", content: "Hi")],
            tools: nil,
            agent: agent,
            provider: provider,
            chatService: fakeChatService,
            toolExecutor: FakeToolExecutor()
        )

        #expect(refresher.refreshCallCount == 1)
        #expect(agent.model == "claude-sonnet-4-6")
        #expect(produced.count == 1)
        #expect(produced[0].content == "Recovered!")
    }

    @Test @MainActor func doesNotRecoverOnUnrelatedError() async throws {
        let (agent, provider, _container) = try makeTestContext()
        _ = _container
        agent.model = "test-model"

        let refresher = FakeProviderModelRefresher(modelsToReturn: ["claude-sonnet-4-6"])
        Container.shared.providerModelRefresher.register { refresher }
        defer { Container.shared.providerModelRefresher.reset() }

        let fakeChatService = FakeChatService()
        fakeChatService.throwOnEventStream(
            OpenAICompatibleClientError.httpError(404, body: "Not Found")
        )

        let loop = AgenticChatLoop(isBootstrap: false)
        await #expect(throws: OpenAICompatibleClientError.self) {
            _ = try await loop.run(
                messages: [ChatMessage(role: "user", content: "Hi")],
                tools: nil,
                agent: agent,
                provider: provider,
                chatService: fakeChatService,
                toolExecutor: FakeToolExecutor()
            )
        }

        #expect(refresher.refreshCallCount == 0)
        #expect(agent.model == "test-model")
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

    // MARK: - InlineToolRunner (local model path)

    /// Verifies that when a local model executes a tool inline via the
    /// ``InlineToolRunner``, the loop records the assistant(tool_calls) +
    /// tool(result) round into `produced` and appends a final assistant message.
    ///
    /// The fake chat service acts as the local model: it invokes the runner
    /// mid-stream, then yields only prose + .finished(.stop), never a
    /// .toolCall event. The loop must not try a second round.
    @Test @MainActor func inlineRunnerRecordsToolRoundInProduced() async throws {
        let (agent, provider, _container) = try makeTestContext()
        _ = _container
        let fakeChatService = FakeChatService()
        let fakeToolExecutor = FakeToolExecutor()

        let call = ToolCall(
            id: "inline_1", type: "function",
            function: .init(name: "read_core", arguments: "{\"core\":\"identity\"}")
        )
        fakeToolExecutor.setResult(
            for: "inline_1", content: "{\"result\":\"I am a test agent.\"}"
        )

        // Queue a tool call to be executed inline by the fake service.
        fakeChatService.enqueueInlineToolCalls([call])

        // After inline execution, the "model" yields prose + stop.
        fakeChatService.enqueueEventStream([
            .contentDelta("Here is what I found."),
            .finished(.stop),
        ])

        let loop = AgenticChatLoop(
            isBootstrap: false,
            permissionPolicy: AlwaysAllowPolicy()
        )

        let produced = try await loop.run(
            messages: [ChatMessage(role: "user", content: "Who am I?")],
            tools: toolDefinitions,
            agent: agent,
            provider: provider,
            chatService: fakeChatService,
            toolExecutor: fakeToolExecutor
        )

        // Expected: assistant(tool_calls:[inline_1]) + tool(result) + assistant(prose)
        #expect(produced.count == 3)
        #expect(produced[0].role == "assistant")
        #expect(produced[0].toolCalls?.first?.id == "inline_1")
        #expect(produced[1].role == "tool")
        #expect(produced[1].toolCallID == "inline_1")
        #expect(produced[2].role == "assistant")
        #expect(produced[2].content == "Here is what I found.")
    }

    /// Verifies that the runner is always passed through to the chat service,
    /// even for cloud providers (where it will be ignored via the default extension).
    @Test @MainActor func inlineRunnerIsPassedToServiceEvenForCloudProvider() async throws {
        let (agent, provider, _container) = try makeTestContext()
        _ = _container
        let fakeChatService = FakeChatService()
        let fakeToolExecutor = FakeToolExecutor()

        fakeChatService.enqueueEventStream([
            .contentDelta("Cloud response."),
            .finished(.stop),
        ])

        let loop = AgenticChatLoop(isBootstrap: false)
        _ = try await loop.run(
            messages: [ChatMessage(role: "user", content: "Hello")],
            tools: nil,
            agent: agent,
            provider: provider,
            chatService: fakeChatService,
            toolExecutor: fakeToolExecutor
        )

        // The runner is always built and passed; the fake captures it.
        #expect(fakeChatService.capturedInlineRunner != nil)
    }
}
