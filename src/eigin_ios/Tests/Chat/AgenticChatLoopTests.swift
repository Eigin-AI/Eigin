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

    @Test @MainActor func segmentEndFiresAtToolRoundWithBufferedProse() async throws {
        let (agent, provider, _container) = try makeTestContext()
        _ = _container
        let fakeChatService = FakeChatService()
        let fakeToolExecutor = FakeToolExecutor()

        let toolCall = ToolCall(
            id: "call_1", type: "function",
            function: .init(name: "read_core", arguments: "{\"core\":\"identity\"}")
        )

        // Round 1: prose followed by a tool call — the round boundary.
        fakeChatService.enqueueEventStream([
            .contentDelta("Let me check my identity. "),
            .toolCall(toolCall),
            .finished(.toolCalls),
        ])
        // Round 2: final content.
        fakeChatService.enqueueEventStream([
            .contentDelta("Got it!"),
            .finished(.stop),
        ])

        fakeToolExecutor.setResult(for: "call_1", content: "{\"result\":\"I am a test agent.\"}")

        var segmentEnds = 0
        let loop = AgenticChatLoop(isBootstrap: false)
        loop.onSegmentEnd = { segmentEnds += 1 }

        _ = try await loop.run(
            messages: [ChatMessage(role: "user", content: "Read my identity")],
            tools: toolDefinitions,
            agent: agent,
            provider: provider,
            chatService: fakeChatService,
            toolExecutor: fakeToolExecutor
        )

        #expect(segmentEnds == 1)
    }

    @Test @MainActor func segmentEndSkippedAtToolRoundWithoutProse() async throws {
        let (agent, provider, _container) = try makeTestContext()
        _ = _container
        let fakeChatService = FakeChatService()
        let fakeToolExecutor = FakeToolExecutor()

        let toolCall = ToolCall(
            id: "call_1", type: "function",
            function: .init(name: "read_core", arguments: "{\"core\":\"identity\"}")
        )

        // Round 1: tool call with no prose before it.
        fakeChatService.enqueueEventStream([
            .toolCall(toolCall),
            .finished(.toolCalls),
        ])
        fakeChatService.enqueueEventStream([
            .contentDelta("Got it!"),
            .finished(.stop),
        ])

        fakeToolExecutor.setResult(for: "call_1", content: "{\"result\":\"I am a test agent.\"}")

        var segmentEnds = 0
        let loop = AgenticChatLoop(isBootstrap: false)
        loop.onSegmentEnd = { segmentEnds += 1 }

        _ = try await loop.run(
            messages: [ChatMessage(role: "user", content: "Read my identity")],
            tools: toolDefinitions,
            agent: agent,
            provider: provider,
            chatService: fakeChatService,
            toolExecutor: fakeToolExecutor
        )

        #expect(segmentEnds == 0)
    }

    @Test @MainActor func segmentEndNotFiredOnContentOnlyTurn() async throws {
        let (agent, provider, _container) = try makeTestContext()
        _ = _container
        let fakeChatService = FakeChatService()
        let fakeToolExecutor = FakeToolExecutor()

        fakeChatService.enqueueEventStream([
            .contentDelta("Just an answer."),
            .finished(.stop),
        ])

        var segmentEnds = 0
        let loop = AgenticChatLoop(isBootstrap: false)
        loop.onSegmentEnd = { segmentEnds += 1 }

        _ = try await loop.run(
            messages: [ChatMessage(role: "user", content: "Hi")],
            tools: nil,
            agent: agent,
            provider: provider,
            chatService: fakeChatService,
            toolExecutor: fakeToolExecutor
        )

        #expect(segmentEnds == 0)
    }

    @Test @MainActor func beforeToolCallRunsBeforeEachToolExecution() async throws {
        let (agent, provider, _container) = try makeTestContext()
        _ = _container
        let fakeChatService = FakeChatService()
        let fakeToolExecutor = FakeToolExecutor()

        let firstCall = ToolCall(
            id: "call_1", type: "function",
            function: .init(name: "read_core", arguments: "{\"core\":\"identity\"}")
        )
        let secondCall = ToolCall(
            id: "call_2", type: "function",
            function: .init(name: "read_core", arguments: "{\"core\":\"user\"}")
        )

        fakeChatService.enqueueEventStream([
            .toolCall(firstCall),
            .toolCall(secondCall),
            .finished(.toolCalls),
        ])
        fakeChatService.enqueueEventStream([
            .contentDelta("Got it!"),
            .finished(.stop),
        ])

        fakeToolExecutor.setResult(for: "read_core", content: "{\"result\":\"ok\"}")

        var beforeCalls: [String] = []
        var afterCalls = 0
        let loop = AgenticChatLoop(isBootstrap: false)
        loop.beforeToolCall = { name in beforeCalls.append(name) }
        loop.afterToolCall = { afterCalls += 1 }

        let produced = try await loop.run(
            messages: [ChatMessage(role: "user", content: "Read my identity")],
            tools: toolDefinitions,
            agent: agent,
            provider: provider,
            chatService: fakeChatService,
            toolExecutor: fakeToolExecutor
        )

        // A wait before and a callback after each tool execution, and execution
        // still completes.
        #expect(beforeCalls == ["read_core", "read_core"])
        #expect(afterCalls == 2)
        #expect(produced.count == 4)
    }

    @Test @MainActor func executingEventIsLiveBeforeBeforeToolCallSuspends() async throws {
        let (agent, provider, _container) = try makeTestContext()
        _ = _container
        let fakeChatService = FakeChatService()
        let fakeToolExecutor = FakeToolExecutor()

        let call = ToolCall(
            id: "call_1", type: "function",
            function: .init(name: "read_core", arguments: "{\"core\":\"identity\"}")
        )

        fakeChatService.enqueueEventStream([
            .toolCall(call),
            .finished(.toolCalls),
        ])
        fakeChatService.enqueueEventStream([
            .contentDelta("Done"),
            .finished(.stop),
        ])
        fakeToolExecutor.setResult(for: "read_core", content: "{\"result\":\"ok\"}")

        // The assistant message commits before tool execution, so a live
        // `.executing` event must exist already when `beforeToolCall` (which
        // can take seconds) suspends — otherwise the committed row reads as
        // done with no output (issue #121).
        var eventStatusAtSuspension: ToolEventStatus?
        let loop = AgenticChatLoop(isBootstrap: false)
        loop.beforeToolCall = { [weak loop] _ in
            eventStatusAtSuspension = loop?.toolEvents.first(where: { $0.id == "call_1" })?.status
        }

        _ = try await loop.run(
            messages: [ChatMessage(role: "user", content: "Read my identity")],
            tools: toolDefinitions,
            agent: agent,
            provider: provider,
            chatService: fakeChatService,
            toolExecutor: fakeToolExecutor
        )

        #expect(eventStatusAtSuspension == .executing)
    }

    /// Tool executor with an `onExecute` hook, to observe live loop state
    /// mid-execution. `FakeToolExecutor` is final, so this is test-local.
    private final class HookToolExecutor: ToolExecutor, @unchecked Sendable {
        var onExecute: (@MainActor () -> Void)?

        @MainActor func execute(_ toolCall: ToolCall, agent: Agent) async -> ToolResult {
            onExecute?()
            return ToolResult(
                toolCallID: toolCall.id,
                content: "{\"result\":\"OK\"}",
                isError: false
            )
        }
    }

    @Test @MainActor func grantingPermissionResumesExecutingStatus() async throws {
        let (agent, provider, _container) = try makeTestContext()
        _ = _container
        let fakeChatService = FakeChatService()

        let call = ToolCall(
            id: "call_1", type: "function",
            function: .init(name: "read_core", arguments: "{\"core\":\"identity\"}")
        )

        fakeChatService.enqueueEventStream([
            .toolCall(call),
            .finished(.toolCalls),
        ])
        fakeChatService.enqueueEventStream([
            .contentDelta("Done"),
            .finished(.stop),
        ])

        // read_core is `.ask` and prompting is allowed, so the event parks
        // in `.awaitingPermission` until the user resolves the prompt.
        let policy = AgentPermissionPolicy(
            builtInGrants: ["read_core": .ask],
            discoveredGrants: [:],
            chatGrants: [],
            canPromptUser: true
        )
        let executor = HookToolExecutor()
        let loop = AgenticChatLoop(isBootstrap: false, permissionPolicy: policy)
        var statusDuringExecution: ToolEventStatus?
        executor.onExecute = { [weak loop] in
            // Issue #121 follow-up: after the grant, the row must say
            // ".executing" again, not stay parked on permission.
            statusDuringExecution = loop?.toolEvents.first(where: { $0.id == "call_1" })?.status
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            loop.resolvePermission(.allowOnce)
        }

        let produced = try await loop.run(
            messages: [ChatMessage(role: "user", content: "Read my identity")],
            tools: toolDefinitions,
            agent: agent,
            provider: provider,
            chatService: fakeChatService,
            toolExecutor: executor
        )

        #expect(statusDuringExecution == .executing)
        #expect(produced.count == 3)
    }

    /// A mid-round prose message's feed row ("msg-<localID>") must match the id the live
    /// streaming row used while that prose was still displaying (`streamingItemID`).
    /// If they diverge, the feed sees a new row identity when the round seals and
    /// re-mounts it — replaying the grow-in animation as a visible flicker (#173).
    @Test @MainActor func proseSealsKeepStreamingRowIdentity() async throws {
        let (agent, provider, _container) = try makeTestContext()
        _ = _container
        let fakeChatService = FakeChatService()
        let fakeToolExecutor = FakeToolExecutor()

        let toolCall = ToolCall(
            id: "call_1", type: "function",
            function: .init(name: "read_core", arguments: "{\"core\":\"identity\"}")
        )

        // Round 1: prose, then a tool call — the flicker-prone mid-round seal.
        fakeChatService.enqueueEventStream([
            .contentDelta("Checking your identity..."),
            .toolCall(toolCall),
            .finished(.toolCalls),
        ])

        // Round 2: final prose.
        fakeChatService.enqueueEventStream([
            .contentDelta("You are a test agent."),
            .finished(.stop),
        ])

        fakeToolExecutor.setResult(for: "call_1", content: "{\"result\":\"I am a test agent.\"}")

        let loop = AgenticChatLoop(isBootstrap: false)

        // Capture the live row id in call order, once per prose segment. Each
        // enqueued round here emits exactly one contentDelta, so the Nth capture
        // corresponds to the Nth committed prose message.
        var streamingIDs: [String] = []
        loop.onContentDelta = { [weak loop] _ in
            guard let loop, let id = loop.streamingItemID else { return }
            streamingIDs.append(id)
        }

        let messages = [ChatMessage(role: "user", content: "Read my identity")]

        let produced = try await loop.run(
            messages: messages,
            tools: toolDefinitions,
            agent: agent,
            provider: provider,
            chatService: fakeChatService,
            toolExecutor: fakeToolExecutor
        )

        let proseMessages = produced.filter { $0.role == "assistant" && $0.content != nil }
        #expect(proseMessages.count == 2)
        #expect(streamingIDs.count == 2)

        // Each committed prose message's feed id must equal the id its live row used
        // while streaming, and the two segments must not collide on the same id.
        for (message, liveID) in zip(proseMessages, streamingIDs) {
            #expect(liveID == "msg-\(message.localID)")
        }
        #expect(streamingIDs[0] != streamingIDs[1])
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

    @Test @MainActor func retriesOnTheModelTheRouterOffers() async throws {
        let (agent, provider, _container) = try makeTestContext()
        _ = _container
        provider.availableModels = ["claude-sonnet-5", "gpt-5.6"]
        agent.model = "claude-sonnet-5"

        let router = FakeModelRouter(retryModels: ["gpt-5.6"])
        Container.shared.modelRouter.register { router }
        defer { Container.shared.modelRouter.reset() }

        let fakeChatService = FakeChatService()
        fakeChatService.throwOnEventStream(OpenAICompatibleClientError.httpError(503, body: nil))
        fakeChatService.enqueueEventStream([.contentDelta("Second try"), .finished(.stop)])

        let loop = AgenticChatLoop(isBootstrap: false)
        let produced = try await loop.run(
            messages: [ChatMessage(role: "user", content: "Hi")],
            tools: nil,
            agent: agent,
            provider: provider,
            chatService: fakeChatService,
            toolExecutor: FakeToolExecutor()
        )

        #expect(produced.count == 1)
        #expect(produced[0].content == "Second try")
        #expect(agent.model == "gpt-5.6")

        // One failed open, one successful stream.
        let outcomes = await router.outcomes()
        #expect(outcomes.count == 2)
        #expect(outcomes.map(\.model) == ["claude-sonnet-5", "gpt-5.6"])
    }

    @Test @MainActor func surfacesTheErrorWhenTheRouterHasNothingLeft() async throws {
        let (agent, provider, _container) = try makeTestContext()
        _ = _container

        Container.shared.modelRouter.register { FakeModelRouter(retryModels: []) }
        defer { Container.shared.modelRouter.reset() }

        let fakeChatService = FakeChatService()
        fakeChatService.throwOnEventStream(OpenAICompatibleClientError.httpError(503, body: nil))

        let loop = AgenticChatLoop(isBootstrap: false)
        await #expect(throws: OpenAICompatibleClientError.self) {
            try await loop.run(
                messages: [ChatMessage(role: "user", content: "Hi")],
                tools: nil,
                agent: agent,
                provider: provider,
                chatService: fakeChatService,
                toolExecutor: FakeToolExecutor()
            )
        }
    }

    @Test @MainActor func anOfflineRouteLeavesTheAgentsOwnModelAlone() async throws {
        let (agent, provider, _container) = try makeTestContext()
        _ = _container
        agent.model = "claude-sonnet-5"

        let fakeChatService = FakeChatService()
        fakeChatService.enqueueEventStream([.contentDelta("On device"), .finished(.stop)])

        // The router routed to an on-device model for this turn only.
        let loop = AgenticChatLoop(isBootstrap: false)
        _ = try await loop.run(
            messages: [ChatMessage(role: "user", content: "Hi")],
            tools: nil,
            agent: agent,
            provider: provider,
            chatService: fakeChatService,
            toolExecutor: FakeToolExecutor(),
            model: "gemma-4-e2b"
        )

        #expect(fakeChatService.lastModel == "gemma-4-e2b")
        // The user's own choice is untouched, so the next online turn returns to it.
        #expect(agent.model == "claude-sonnet-5")
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

    /// The pre-stream wait must land in ``timeToFirstToken``, not be measured away as zero.
    @Test @MainActor func recordsTimeToFirstTokenFromRequestDispatch() async throws {
        let (agent, provider, _container) = try makeTestContext()
        _ = _container

        let router = FakeModelRouter()
        Container.shared.modelRouter.register { router }
        defer { Container.shared.modelRouter.reset() }

        let fakeChatService = FakeChatService()
        // Hold the response, then deliver the first token as soon as the stream opens.
        fakeChatService.delayBeforeStream(.milliseconds(200))
        fakeChatService.enqueueEventStream([.contentDelta("Hi"), .finished(.stop)])

        let loop = AgenticChatLoop(isBootstrap: false)
        _ = try await loop.run(
            messages: [ChatMessage(role: "user", content: "Hi")],
            tools: nil,
            agent: agent,
            provider: provider,
            chatService: fakeChatService,
            toolExecutor: FakeToolExecutor()
        )

        let outcomes = await router.outcomes()
        let ttft = try #require(outcomes.last?.timeToFirstToken)
        #expect(ttft > .milliseconds(100))
    }
}
