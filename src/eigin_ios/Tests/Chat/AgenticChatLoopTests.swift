@testable import Eigin
import Factory
import Foundation
import os
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

    @Test(arguments: ["same-model", "retry", "hedge"])
    @MainActor func dispatchesSessionEffortAcrossTurnsAndFallbacks(mode: String) async throws {
        let (agent, provider, container) = try makeTestContext()
        _ = container
        provider.baseURL = "https://api.mistral.ai/v1"
        provider.availableModels = mode == "same-model"
            ? ["mistral-large-4-0"] : ["mistral-medium-3-5", "mistral-large-4-0"]
        let router = DefaultModelRouter(
            reachability: FakeNetworkReachability(), localModelReadiness: { false }
        )
        Container.shared.modelRouter.register { router }
        defer { Container.shared.modelRouter.reset() }
        let conversation = UUID()
        let routingProvider = RoutingProvider(
            id: provider.id, name: provider.name, baseURL: provider.baseURL,
            availableModels: provider.availableModels
        )
        let service = ObservedChatService { _, _, _ in }
        let calls = OSAllocatedUnfairLock(initialState: [(String, ReasoningEffort?)]())
        service.observeEffort = { model, effort in calls.withLock { $0.append((model, effort)) } }
        let loop = AgenticChatLoop(isBootstrap: false)
        let texts = ["Hello", "Analyze and compare trade-offs step by step. Explain why.", "Thanks"]
        var firstModel = ""
        for (index, text) in texts.enumerated() {
            let request = RouteRequest(
                currentProviderID: provider.id, currentModel: agent.model, isAuto: true,
                requirements: RouteRequirements(), providers: [routingProvider],
                conversationID: conversation, lastUserMessage: text
            )
            let route = await router.resolve(request)
            agent.model = route.model
            loop.activeModel = route.model
            if index == 0 { firstModel = route.model }
            if index == 2, mode == "retry" {
                service.scripted.throwOnEventStream(OpenAICompatibleClientError.httpError(
                    503,
                    body: nil
                ))
            }
            if index == 2, mode == "hedge" {
                service.scripted.delayBeforeStream(.seconds(7))
            }
            service.scripted.enqueueEventStream([.contentDelta("Answer"), .finished(.stop)])
            if index == 2, mode == "hedge" {
                service.scripted.enqueueEventStream([.contentDelta("Answer"), .finished(.stop)])
            }
            let stream = try await loop.openStream(
                chatService: service, provider: provider, agent: agent,
                messages: [ChatMessage(role: "user", content: text)], tools: nil,
                cacheKey: nil, routing: request, conversationID: conversation
            )
            for try await _ in stream.stream {}
        }
        let dispatched = calls.withLock { $0 }
        #expect(dispatched[0].1 == .low)
        #expect(dispatched[1].0 == firstModel)
        #expect(dispatched.dropFirst().allSatisfy { $0.1 == .high })
        if mode == "same-model" {
            #expect(dispatched.count == 3)
            #expect(dispatched.allSatisfy { $0.0 == firstModel })
        } else {
            #expect(dispatched.count == 4)
            #expect(dispatched.last?.0 != firstModel)
        }
    }

    @Test(arguments: [false, true], [false, true])
    @MainActor func retainsPrivateHistoryAcrossToolRounds(
        prose: Bool,
        checkpoint: Bool
    ) async throws {
        let (agent, provider, container) = try makeTestContext()
        _ = container
        provider.baseURL = "https://api.mistral.ai/v1"
        agent.model = "mistral-large-4-0"
        let service = FakeChatService()
        let history = try MistralReasoningHistory(
            origin: ReasoningOrigin(
                providerID: provider.id,
                endpoint: provider.baseURL,
                model: agent.model
            ),
            parts: [MistralContentPart(type: "thinking", thinking: [.text("hidden")])]
                + (prose ? [.text("Checking")] : [])
        ).stored()
        let call = ToolCall(
            id: "call00001",
            type: "function",
            function: .init(name: "lookup", arguments: "{}")
        )
        service.enqueueEventStream((prose ? [.contentDelta("Checking")] : []) + [
            .reasoningHistory(history), .toolCall(call), .finished(.toolCalls),
        ])
        service.enqueueEventStream([.contentDelta("Answer"), .finished(.stop)])
        let loop = AgenticChatLoop(isBootstrap: false)
        var savedCheckpoint: [ChatMessage] = []
        if checkpoint {
            loop.onToolsChanged = {
                savedCheckpoint = loop.stop()
                return ([], FakeToolExecutor())
            }
        }
        _ = try await loop.run(
            messages: [ChatMessage(role: "user", content: "Hello")], tools: nil,
            agent: agent, provider: provider, chatService: service, toolExecutor: FakeToolExecutor()
        )
        var continuation = service.capturedEventMessages
        if checkpoint {
            let store = try ModelContainer(
                for: Schema(SchemaV12.models, version: SchemaV12.versionIdentifier),
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
            for message in savedCheckpoint {
                store.mainContext.insert(Message.from(message))
            }
            try store.mainContext.save()
            continuation = try ModelContext(store)
                .fetch(FetchDescriptor<Message>(sortBy: [SortDescriptor(\.timestamp)]))
                .map { $0.toChatMessage() }
        }
        #expect(continuation.contains { $0.role == "tool" && $0.toolCallID == call.id })
        #expect(!continuation.contains { $0.content?.contains("hidden") == true })
        let url = provider.baseURL + "/chat/completions"
        FakeURLProtocol.stubResponse(
            for: url,
            data: Data(
                "data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n"
                    .utf8
            ),
            statusCode: 200
        )
        let client = OpenAICompatibleClient(
            baseURL: provider.baseURL,
            apiToken: "test",
            session: FakeURLProtocol.fakeSession(),
            providerID: provider.id
        )
        let stream = try await client.chatCompletionEventStream(
            messages: continuation,
            model: agent.model,
            tools: nil
        )
        for try await _ in stream {}
        let body = try #require(FakeURLProtocol.lastRequestBody(for: url))
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let messages = try #require(json["messages"] as? [[String: Any]])
        let assistant = try #require(messages.first { $0["role"] as? String == "assistant" })
        let parts = try #require(assistant["content"] as? [[String: Any]])
        #expect((parts.first?["thinking"] as? [[String: String]])?.first?["text"] == "hidden")
        #expect((assistant["tool_calls"] as? [[String: Any]])?.first?["id"] as? String == call.id)
        #expect(parts.count == (prose ? 2 : 1))
    }

    @Test(arguments: ["", " \n\t"])
    @MainActor func recoversEmptyFinalReply(empty: String) async throws {
        let (agent, provider, container) = try makeTestContext()
        _ = container
        let service = FakeChatService()
        service.enqueueEventStream([.contentDelta(empty), .finished(.stop)])
        service.enqueueEventStream([.contentDelta("Done."), .finished(.stop)])
        let loop = AgenticChatLoop(isBootstrap: false)
        let messages = [
            ChatMessage(role: "system", content: "Stable system prompt"),
            ChatMessage(role: "user", content: "Help"),
        ]
        let produced = try await loop.run(
            messages: messages, tools: nil,
            agent: agent, provider: provider, chatService: service, toolExecutor: FakeToolExecutor()
        )
        #expect(produced.last?.content == "Done.")
        #expect(loop.roundsExecuted == 2)
        #expect(service.capturedEventMessages.first?.content == messages.first?.content)
        #expect(service.capturedEventMessages.last?.role == "user")
        #expect(service.capturedEventMessages.last?.content?.contains("<system_hint>") == true)
        #expect(service.capturedEventMessages.last?.content?
            .contains(Prompt.Hints.Continuation.missingReply) == true)
        #expect(service.capturedEventMessages.count == messages.count)
        #expect(messages.last?.content == "Help")
        #expect(!produced.contains { $0.role == "system" || $0.role == "user" })
    }

    @Test(arguments: [false, true])
    @MainActor func recoveryHintAppliesOnlyToTheRecoveryRequest(hasUserMessage: Bool) async throws {
        let (agent, provider, container) = try makeTestContext()
        _ = container
        let requests = OSAllocatedUnfairLock(initialState: [[ChatMessage]]())
        let service = ObservedChatService { _, messages, _ in
            requests.withLock { $0.append(messages) }
        }
        let call = ToolCall(
            id: "work",
            type: "function",
            function: .init(name: "read_core", arguments: "{}")
        )
        service.scripted.enqueueEventStreams([
            [.finished(.stop)], [.toolCall(call), .finished(.toolCalls)],
            [.contentDelta("Done."), .finished(.stop)],
        ])
        var messages = [ChatMessage(role: "system", content: "Stable system prompt")]
        if hasUserMessage {
            messages.append(ChatMessage(
                role: "user",
                content: "Help\n\n<system_hint>Existing context</system_hint>"
            ))
        }
        let loop = AgenticChatLoop(isBootstrap: false)
        let produced = try await loop.run(
            messages: messages,
            tools: nil,
            agent: agent,
            provider: provider,
            chatService: service,
            toolExecutor: FakeToolExecutor()
        )
        let captured = requests.withLock { $0 }
        #expect(captured.count == 3)
        for (index, request) in captured.enumerated() {
            #expect(request.first?.content == messages.first?.content)
            #expect(request
                .contains { ($0.content ?? "").contains(Prompt.Hints.Continuation.missingReply) } ==
                (index == 1))
        }
        let recoveryUser = try #require(captured[1].last(where: { $0.role == "user" }))
        #expect(recoveryUser.content?.contains("<system_hint>") == true)
        if hasUserMessage {
            #expect(recoveryUser.localID == messages.last?.localID)
            #expect(recoveryUser.content?.contains("Existing context") == true)
        }
        #expect(!produced
            .contains { ($0.content ?? "").contains(Prompt.Hints.Continuation.missingReply) })
        #expect(!messages
            .contains { ($0.content ?? "").contains(Prompt.Hints.Continuation.missingReply) })
    }

    @Test(arguments: ["empty", "eof", "network"])
    @MainActor func recoversAfterToolsWithoutRepeatingWork(ending: String) async throws {
        let (agent, provider, container) = try makeTestContext()
        _ = container
        let service = FakeChatService()
        let executor = FakeToolExecutor()
        let call = ToolCall(
            id: "work",
            type: "function",
            function: .init(name: "read_core", arguments: "{}")
        )
        service.enqueueEventStream([
            .contentDelta("Checking."),
            .toolCall(call),
            .finished(.toolCalls),
        ])
        service.enqueueEventStream(
            ending == "empty" ? [.finished(.stop)] : [.contentDelta("The result is")],
            endingWith: ending == "network" ? URLError(.networkConnectionLost) : nil
        )
        service.enqueueEventStream([.contentDelta("Done."), .finished(.stop)])
        let loop = AgenticChatLoop(isBootstrap: false)
        let produced = try await loop.run(
            messages: [ChatMessage(role: "user", content: "Help")], tools: toolDefinitions,
            agent: agent, provider: provider, chatService: service, toolExecutor: executor
        )
        #expect(executor.calls.count == 1)
        #expect(loop.roundsExecuted == 3)
        #expect(produced.last?.content == "Done.")
        #expect(service.capturedEventMessages.contains { $0.toolCallID == "work" })
        if ending != "empty" {
            #expect(service.capturedEventMessages.contains { $0.content == "The result is" })
        }
    }

    @Test @MainActor func repeatedSilenceOffersContinuationAndPreservesTools() async throws {
        let (agent, provider, container) = try makeTestContext()
        _ = container
        let service = FakeChatService()
        let executor = FakeToolExecutor()
        let call = ToolCall(
            id: "work",
            type: "function",
            function: .init(name: "read_core", arguments: "{}")
        )
        service.enqueueEventStream([.toolCall(call), .finished(.toolCalls)])
        service.enqueueEventStreams([[.finished(.stop)], [.finished(.stop)]])
        let loop = AgenticChatLoop(isBootstrap: false)
        do {
            _ = try await loop.run(
                messages: [],
                tools: toolDefinitions,
                agent: agent,
                provider: provider,
                chatService: service,
                toolExecutor: executor
            )
            Issue.record("Expected missing reply")
        } catch let error as TurnCompletionError {
            #expect(ConnectionError(from: error).recovery == .continueTurn)
        }
        #expect(loop.roundsExecuted == 3)
        #expect(executor.calls.count == 1)
        #expect(loop.buildCheckpoint().contains { $0.toolCallID == "work" })
    }

    @Test @MainActor func interruptedToolFragmentsAreNeverExecuted() async throws {
        let (agent, provider, container) = try makeTestContext()
        _ = container
        let service = FakeChatService()
        let executor = FakeToolExecutor()
        let call = ToolCall(
            id: "fragment",
            type: "function",
            function: .init(name: "read_core", arguments: "{ truncated")
        )
        service.enqueueEventStream([.toolCall(call)])
        service.enqueueEventStream([.contentDelta("Please try again."), .finished(.stop)])
        let loop = AgenticChatLoop(isBootstrap: false)
        _ = try await loop.run(
            messages: [],
            tools: toolDefinitions,
            agent: agent,
            provider: provider,
            chatService: service,
            toolExecutor: executor
        )
        #expect(executor.calls.isEmpty)
        #expect(!service.capturedEventMessages.contains { !($0.toolCalls ?? []).isEmpty })
    }

    @Test @MainActor func sharedBudgetPreservesTextBeforeUnexecutedTools() async throws {
        let (agent, provider, container) = try makeTestContext()
        _ = container
        let service = FakeChatService()
        let executor = FakeToolExecutor()
        let call = ToolCall(
            id: "pending",
            type: "function",
            function: .init(name: "read_core", arguments: "{}")
        )
        service.enqueueEventStream([.finished(.stop)])
        service.enqueueEventStream([.contentDelta("Partial answer"), .toolCall(call)])
        let loop = AgenticChatLoop(isBootstrap: false)
        do {
            _ = try await loop.run(
                messages: [],
                tools: toolDefinitions,
                agent: agent,
                provider: provider,
                chatService: service,
                toolExecutor: executor
            )
            Issue.record("Expected exhausted recovery")
        } catch let error as StreamCompletionError {
            guard case .interrupted = error else { Issue.record("Wrong failure"); return }
        }
        #expect(loop.roundsExecuted == 2)
        #expect(executor.calls.isEmpty)
        #expect(loop.buildCheckpoint().last?.content == "Partial answer")
        #expect(loop.buildCheckpoint().allSatisfy { ($0.toolCalls ?? []).isEmpty })
        loop.settle()
        #expect(loop.buildCheckpoint().isEmpty)
    }

    @Test @MainActor func explicitToolTerminationDoesNotNeedReply() async throws {
        let (agent, provider, container) = try makeTestContext()
        _ = container
        let service = FakeChatService()
        let call = ToolCall(
            id: "done",
            type: "function",
            function: .init(name: "read_core", arguments: "{}")
        )
        service.enqueueEventStream([.toolCall(call), .finished(.toolCalls)])
        let loop = AgenticChatLoop(isBootstrap: false)
        loop.shouldTerminate = { true }
        let produced = try await loop.run(
            messages: [],
            tools: toolDefinitions,
            agent: agent,
            provider: provider,
            chatService: service,
            toolExecutor: FakeToolExecutor()
        )
        #expect(loop.roundsExecuted == 1)
        #expect(produced.last?.toolCallID == "done")
    }

    @Test @MainActor func stoppingDuringRecoveryKeepsCompletedTools() async throws {
        let (agent, provider, container) = try makeTestContext()
        _ = container
        let loop = AgenticChatLoop(isBootstrap: false)
        let saved = OSAllocatedUnfairLock(initialState: [ChatMessage]())
        let service = ObservedChatService { index, _, _ in
            if index == 2 {
                let checkpoint = loop.stop()
                saved.withLock { $0 = checkpoint }
            }
        }
        let call = ToolCall(
            id: "done",
            type: "function",
            function: .init(name: "read_core", arguments: "{}")
        )
        service.scripted.enqueueEventStreams([
            [.toolCall(call), .finished(.toolCalls)], [.finished(.stop)], [.finished(.stop)],
        ])
        _ = try await loop.run(
            messages: [],
            tools: toolDefinitions,
            agent: agent,
            provider: provider,
            chatService: service,
            toolExecutor: FakeToolExecutor()
        )
        #expect(saved.withLock { $0.contains { $0.toolCallID == "done" } })
    }

    @Test @MainActor func stoppedBatchPersistsPairedResultsAndContinuesWithoutReplay() async throws {
        let (agent, provider, container) = try makeTestContext()
        _ = container
        let loop = AgenticChatLoop(isBootstrap: false)
        let executor = FakeToolExecutor()
        let service = FakeChatService()
        let calls = ["first", "second", "third"].map {
            ToolCall(id: $0, type: "function", function: .init(name: $0, arguments: "{}"))
        }
        executor.setResult(for: "first", content: "Completed action")
        service.enqueueEventStream(calls.map { .toolCall($0) } + [.finished(.toolCalls)])
        var checkpoint: [ChatMessage] = []
        loop.beforeToolCall = { name in
            if name == "second" { checkpoint = loop.stop() }
        }
        _ = try await loop.run(
            messages: [],
            tools: nil,
            agent: agent,
            provider: provider,
            chatService: service,
            toolExecutor: executor
        )
        #expect(executor.calls.map(\.id) == ["first"])
        let store = try ModelContainer(
            for: Schema(SchemaV12.models, version: SchemaV12.versionIdentifier),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        for message in checkpoint {
            store.mainContext.insert(Message.from(message))
        }
        try store.mainContext.save()
        let persisted = try ModelContext(store)
            .fetch(FetchDescriptor<Message>(sortBy: [SortDescriptor(\.timestamp)]))
            .map { $0.toChatMessage() }
        #expect(persisted.filter { $0.toolCallID == "first" }
            .map(\.content) == ["Completed action"])
        for call in calls {
            #expect(persisted.count { $0.toolCallID == call.id } == 1)
        }
        #expect(persisted.first?.toolCalls?.map(\.id) == calls.map(\.id))
        loop.settle()
        loop.beforeToolCall = nil
        service.enqueueEventStream([
            .contentDelta("The first action completed. The remaining actions were interrupted."),
            .finished(.stop),
        ])
        let reply = try await loop.run(
            messages: persisted,
            tools: nil,
            agent: agent,
            provider: provider,
            chatService: service,
            toolExecutor: executor,
            continuationInstruction: Prompt.Hints.Continuation.interrupted
        )
        #expect(reply.last?.content?.contains("first action completed") == true)
        #expect(executor.calls.map(\.id) == ["first"])
        for call in calls {
            #expect(service.capturedEventMessages.count { $0.toolCallID == call.id } == 1)
        }
    }

    @Test(arguments: [StreamCompletionError.outputLimit, .policyStop, .invalidToolCall])
    @MainActor func terminalFailuresDoNotContinue(failure: StreamCompletionError) async throws {
        let (agent, provider, container) = try makeTestContext()
        _ = container
        let service = FakeChatService()
        service.enqueueEventStream([.contentDelta("Partial response")], endingWith: failure)
        service.enqueueEventStream([.contentDelta("Unexpected continuation"), .finished(.stop)])
        let loop = AgenticChatLoop(isBootstrap: false)
        await #expect(throws: StreamCompletionError.self) {
            try await loop.run(
                messages: [],
                tools: nil,
                agent: agent,
                provider: provider,
                chatService: service,
                toolExecutor: FakeToolExecutor()
            )
        }
        #expect(loop.roundsExecuted == 1)
    }

    @Test(arguments: ["arguments", "id", "name"])
    @MainActor func invalidToolBatchNeverExecutes(invalidField: String) async throws {
        let (agent, provider, container) = try makeTestContext()
        _ = container
        let call = ToolCall(
            id: invalidField == "id" ? "" : "call",
            type: "function",
            function: .init(
                name: invalidField == "name" ? "" : "read_core",
                arguments: invalidField == "arguments" ? "[]" : "{}"
            )
        )
        let service = FakeChatService()
        service.enqueueEventStream([.toolCall(call), .finished(.toolCalls)])
        let executor = FakeToolExecutor()
        let loop = AgenticChatLoop(isBootstrap: false)
        await #expect(throws: StreamCompletionError.self) {
            try await loop.run(
                messages: [],
                tools: nil,
                agent: agent,
                provider: provider,
                chatService: service,
                toolExecutor: executor
            )
        }
        #expect(executor.calls.isEmpty)
        #expect(loop.roundsExecuted == 1)
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
