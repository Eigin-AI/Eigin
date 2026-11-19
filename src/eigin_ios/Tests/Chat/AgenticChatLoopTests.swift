@testable import Eigin
import EiginSDK
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

    @Test(arguments: ["same-model", "retry", "hedge"], [false, true])
    @MainActor func dispatchesSessionEffortAcrossTurnsAndFallbacks(
        mode: String,
        early: Bool
    ) async throws {
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
                conversationID: conversation, lastUserMessage: text,
                turnContext: early ? RoutingTurnContext(responseTurnCount: 0) : nil
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
        #expect(dispatched.dropFirst().allSatisfy {
            $0.1 == ($0.0 == "mistral-large-4-0"
                ? (early ? .low : .medium) : (early ? ReasoningEffort.none : .high))
        })
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
                for: Schema(SchemaV15.models, version: SchemaV15.versionIdentifier),
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

    @Test @MainActor func streamReportedSilenceRechecksTerminationBeforeRecovery() async throws {
        let (agent, provider, container) = try makeTestContext()
        _ = container
        let loop = AgenticChatLoop(isBootstrap: false)
        var checks = 0
        loop.shouldTerminate = { checks += 1; return checks == 2 }
        let service = FakeChatService()
        service.enqueueEventStream(
            [.contentDelta("Partial")],
            endingWith: TurnCompletionError.missingReply
        )
        let produced = try await loop.run(
            messages: [], tools: nil, agent: agent, provider: provider,
            chatService: service, toolExecutor: FakeToolExecutor()
        )
        #expect(produced.isEmpty)
        #expect(loop.roundsExecuted == 1)
        #expect(checks == 2)
    }

    @Test @MainActor func cancellationDuringEmptyReplyCheckPrecedesRecovery() async throws {
        let (agent, provider, container) = try makeTestContext()
        _ = container
        let loop = AgenticChatLoop(isBootstrap: false)
        loop.shouldTerminate = {
            withUnsafeCurrentTask { $0?.cancel() }
            return false
        }
        let service = FakeChatService()
        service.enqueueEventStream([.contentDelta(" "), .finished(.stop)])
        let task = Task {
            try await loop.run(
                messages: [], tools: nil, agent: agent, provider: provider,
                chatService: service, toolExecutor: FakeToolExecutor()
            )
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(loop.roundsExecuted == 1)
    }

    @Test @MainActor func returnsCompletedToolsAtRoundLimit() async throws {
        let (agent, provider, container) = try makeTestContext()
        _ = container
        let service = FakeChatService()
        let executor = FakeToolExecutor()
        for index in 0 ..< 40 {
            service.enqueueEventStream([
                .toolCall(ToolCall(
                    id: "call-\(index)",
                    type: "function",
                    function: .init(name: "read_core", arguments: "{}")
                )),
                .finished(.toolCalls),
            ])
        }
        let loop = AgenticChatLoop(isBootstrap: false)
        var refreshes = 0
        loop.onToolsChanged = {
            refreshes += 1
            return (tools: [], executor: executor)
        }
        let produced = try await loop.run(
            messages: [ChatMessage(role: "user", content: "Keep working")], tools: nil,
            agent: agent, provider: provider, chatService: service, toolExecutor: executor
        )
        #expect(loop.roundsExecuted == 40)
        #expect(executor.calls.count == 40)
        #expect(refreshes == 40)
        #expect(produced.count(where: { $0.role == "tool" }) == 40)
        #expect(produced.last?.toolCallID == "call-39")
    }

    @Test(arguments: [false, true])
    @MainActor func recoveryCausesShareOneAllowance(emptyFirst: Bool) async throws {
        let (agent, provider, container) = try makeTestContext()
        _ = container
        let service = FakeChatService()
        if emptyFirst { service.enqueueEventStream([.finished(.stop)]) }
        service.enqueueEventStream(
            [.contentDelta("Partial")],
            endingWith: URLError(.networkConnectionLost)
        )
        if !emptyFirst { service.enqueueEventStream([.finished(.stop)]) }
        let loop = AgenticChatLoop(isBootstrap: false)
        do {
            _ = try await loop.run(
                messages: [ChatMessage(role: "user", content: "Help")], tools: nil,
                agent: agent, provider: provider, chatService: service,
                toolExecutor: FakeToolExecutor()
            )
            Issue.record("Expected the second failure to exhaust recovery")
        } catch {
            if emptyFirst {
                #expect((error as? URLError)?.code == .networkConnectionLost)
            } else {
                #expect(error is TurnCompletionError)
            }
        }
        #expect(loop.roundsExecuted == 2)
        #expect(loop.buildCheckpoint().contains { $0.content == "Partial" })
    }

    @Test(arguments: ["", " \n\t", "\u{0085}\u{00A0}\u{200B}\u{2028}\u{3000}"])
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
        #expect(produced.last?.content == loop.fullText)
        #expect(produced.last?.content == loop.displayedText)
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

    @Test(arguments: [false, true])
    @MainActor func stoppedOptionsCannotAppendASecondResultAfterSettling(
        cancelTask: Bool
    ) async throws {
        let (agent, provider, container) = try makeTestContext()
        _ = container
        let loop = AgenticChatLoop(isBootstrap: false)
        let service = FakeChatService()
        let call = ToolCall(
            id: "options", type: "function",
            function: .init(name: "present_options", arguments: "{}")
        )
        service.enqueueEventStream([.toolCall(call), .finished(.toolCalls)])
        let (entered, signal) = AsyncStream<Void>.makeStream()
        let executor = SuspendedOptionsExecutor { _ in
            signal.yield(())
            _ = await loop.presentOptions(OptionSet(id: call.id, question: nil, options: []))
        }
        let task = Task {
            try await loop.run(
                messages: [], tools: nil, agent: agent, provider: provider,
                chatService: service, toolExecutor: executor
            )
        }
        for await _ in entered {
            break
        }
        let checkpoint = loop.stop()
        loop.settle()
        if cancelTask { task.cancel() }
        do {
            let returned = try await task.value
            #expect(returned.isEmpty)
        } catch is CancellationError {
            #expect(cancelTask)
        }

        #expect(checkpoint.count { $0.toolCallID == call.id } == 1)
        #expect(loop.buildCheckpoint().isEmpty)
        let lateCommit = loop.completeRound()
        #expect(lateCommit.isEmpty)
        #expect((checkpoint + lateCommit).count { $0.toolCallID == call.id } == 1)
    }

    @Test @MainActor func cancelledOptionsCannotClearReplacementInteraction() async throws {
        let (agent, provider, container) = try makeTestContext()
        _ = container
        let loop = AgenticChatLoop(isBootstrap: false)
        let service = FakeChatService()
        let calls = ["old", "new"].map {
            ToolCall(
                id: $0,
                type: "function",
                function: .init(name: "present_options", arguments: "{}")
            )
        }
        service.enqueueEventStreams(calls.map { [.toolCall($0), .finished(.toolCalls)] }
            + [[.contentDelta("Done"), .finished(.stop)]])
        let (entered, signal) = AsyncStream<Void>.makeStream()
        var entry = entered.makeAsyncIterator()
        let (returning, returningSignal) = AsyncStream<Void>.makeStream()
        var releaseOld: CheckedContinuation<Void, Never>?
        let executor = SuspendedOptionsExecutor { call in
            signal.yield(())
            _ = await loop.presentOptions(OptionSet(id: call.id, question: nil, options: []))
            if call.id == "old" {
                await withCheckedContinuation {
                    releaseOld = $0
                    returningSignal.yield(())
                }
            }
        }
        let oldTask = Task {
            try await loop.run(
                messages: [],
                tools: nil,
                agent: agent,
                provider: provider,
                chatService: service,
                toolExecutor: executor
            )
        }
        _ = await entry.next()
        _ = loop.stop()
        loop.settle()
        oldTask.cancel()
        for await _ in returning {
            break
        }
        let replacement = Task {
            try await loop.run(
                messages: [],
                tools: nil,
                agent: agent,
                provider: provider,
                chatService: service,
                toolExecutor: executor
            )
        }
        _ = await entry.next()
        #expect(loop.pendingOptions?.id == "new")
        releaseOld?.resume()
        do { _ = try await oldTask.value } catch is CancellationError {}
        #expect(loop.isAwaitingUserInteraction)
        #expect(loop.pendingOptions?.id == "new")
        #expect(!loop.buildCheckpoint().contains { $0.toolCallID == "old" })
        loop.resolveOptions(.selected(label: "Continue"))
        let completed = try await replacement.value
        #expect(completed.count { $0.toolCallID == "new" } == 1)
    }

    @Test @MainActor func stopDuringStreamingPreservesPartialProseIdentity() async throws {
        let (agent, provider, container) = try makeTestContext()
        _ = container
        let loop = AgenticChatLoop(isBootstrap: false)
        let service = FakeChatService()
        service.enqueueEventStream([
            .contentDelta("Partial"),
            .contentDelta(" discarded"),
            .finished(.stop),
        ])
        var checkpoint: [ChatMessage] = []
        loop.onContentDelta = { _ in checkpoint = loop.stop() }
        let produced = try await loop.run(
            messages: [], tools: nil, agent: agent, provider: provider,
            chatService: service, toolExecutor: FakeToolExecutor()
        )
        #expect(produced.isEmpty)
        #expect(checkpoint.map(\.content) == ["Partial"])
        #expect(checkpoint.first?.toolCalls == nil)
        #expect(loop.buildCheckpoint().map(\.localID) == checkpoint.map(\.localID))
        loop.settle()
        #expect(loop.buildCheckpoint().isEmpty)
    }

    @Test @MainActor func checkpointBeforeExecutionClosesBatchWithoutDuplicatingProse(
    ) async throws {
        let (agent, provider, container) = try makeTestContext()
        _ = container
        let loop = AgenticChatLoop(isBootstrap: false)
        let executor = FakeToolExecutor()
        let service = FakeChatService()
        let calls = ["a", "b"].map {
            ToolCall(id: $0, type: "function", function: .init(name: "read_core", arguments: "{}"))
        }
        service.enqueueEventStream([.contentDelta("Working")] + calls.map { .toolCall($0) }
            + [.finished(.toolCalls)])
        var checkpoint: [ChatMessage] = []
        loop.beforeToolCall = { _ in checkpoint = loop.stop() }
        _ = try await loop.run(
            messages: [], tools: nil, agent: agent, provider: provider,
            chatService: service, toolExecutor: executor
        )
        #expect(executor.calls.isEmpty)
        #expect(checkpoint.map(\.role) == ["assistant", "tool", "tool"])
        #expect(checkpoint.first?.content == "Working")
        #expect(checkpoint.first?.toolCalls?.map(\.id) == ["a", "b"])
        #expect(checkpoint.dropFirst().map(\.content)
            == [ToolResult.interruptedContent, ToolResult.interruptedContent])
        #expect(loop.buildCheckpoint().first?.localID == checkpoint.first?.localID)
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
            if name == "second" {
                checkpoint = loop.stop()
                let repeated = loop.buildCheckpoint()
                #expect(repeated.map(\.content) == checkpoint.map(\.content))
                #expect(repeated.map(\.toolCallID) == checkpoint.map(\.toolCallID))
                #expect(repeated.prefix(2).map(\.localID) == checkpoint.prefix(2).map(\.localID))
            }
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

    @Test(arguments: [true, false])
    @MainActor func resourceLimitPreservesCurrentAdapterPolicy(local: Bool) async throws {
        let (agent, provider, container) = try makeTestContext()
        _ = container
        if local { provider.baseURL = "local://test" }
        let service = FakeChatService()
        let limit = EiginSDK.Experimental.Inference.Failure.LimitExceeded(limit: "stream")
        service.enqueueEventStream(
            [.contentDelta("Partial")],
            endingWith: InferenceSDKConversion.error(limit)
        )
        service.enqueueEventStream([.contentDelta("Done"), .finished(.stop)])
        let loop = AgenticChatLoop(isBootstrap: false)
        do {
            let produced = try await loop.run(
                messages: [], tools: nil, agent: agent, provider: provider,
                chatService: service, toolExecutor: FakeToolExecutor()
            )
            #expect(!local)
            #expect(produced.map(\.content) == ["Partial", "Done"])
        } catch StreamCompletionError.interrupted {
            #expect(local)
            #expect(loop.buildCheckpoint().last?.content == "Partial")
        }
        #expect(loop.roundsExecuted == (local ? 1 : 2))
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

    @Test(arguments: ["approve", "deny", "stop"])
    @MainActor func multiplePermissionsIgnoreLateResponses(action: String) async throws {
        let approveSecond = action == "approve"
        let (agent, provider, container) = try makeTestContext()
        _ = container
        let service = FakeChatService()
        let executor = FakeToolExecutor()
        let calls = ["permission-a", "permission-b"].map {
            ToolCall(id: $0, type: "function", function: .init(name: "read_core", arguments: "{}"))
        }
        service.enqueueEventStream(calls.map { .toolCall($0) } + [.finished(.toolCalls)])
        service.enqueueEventStream([.contentDelta("Done"), .finished(.stop)])
        let loop = AgenticChatLoop(isBootstrap: false, permissionPolicy: AgentPermissionPolicy(
            builtInGrants: ["read_core": .ask], discoveredGrants: [:],
            chatGrants: [], canPromptUser: true
        ))
        let task = Task { @MainActor in
            try await loop.run(
                messages: [ChatMessage(role: "user", content: "Read twice")],
                tools: toolDefinitions, agent: agent, provider: provider,
                chatService: service, toolExecutor: executor
            )
        }
        defer { _ = loop.stop(); task.cancel() }
        try await waitForPermission("permission-a", in: loop)
        loop.resolvePermission(.allowOnce, requestID: "permission-a")
        try await waitForPermission("permission-b", in: loop)
        loop.resolvePermission(.deny, requestID: "permission-a")
        loop.resolvePermission(.allowOnce, requestID: "unknown")
        #expect(loop.pendingPermission?.id == "permission-b")
        #expect(executor.calls.map(\.id) == ["permission-a"])
        if action == "stop" {
            var queuedStarted = false
            let queued = Task {
                queuedStarted = true
                return await loop.requestPermission(PermissionRequest(
                    id: "permission-c", toolName: "read_core", toolDisplayName: "Read",
                    disclosure: nil
                ))
            }
            try await waitForPermissionCondition { queuedStarted }
            let checkpoint = loop.stop()
            #expect(checkpoint.count { $0.toolCallID == "permission-a" } == 1)
            #expect(checkpoint.filter { $0.toolCallID == "permission-b" }.map(\.content)
                == [ToolResult.interruptedContent])
            loop.resolvePermission(.allowOnce, requestID: "permission-b")
            #expect(await queued.value == .deny)
            _ = try await task.value
            #expect(loop.pendingPermission == nil)
            #expect(executor.calls.map(\.id) == ["permission-a"])
            return
        }
        loop.resolvePermission(approveSecond ? .allowOnce : .deny, requestID: "permission-b")
        let produced = try await task.value
        #expect(executor.calls
            .map(\.id) == (approveSecond ? ["permission-a", "permission-b"] : ["permission-a"]))
        let secondResult = try #require(produced.first { $0.toolCallID == "permission-b" })
        #expect((secondResult.content?.contains("User denied this action.") == true) ==
            !approveSecond)
    }

    @MainActor
    private func waitForPermission(_ id: String, in loop: AgenticChatLoop) async throws {
        try await waitForPermissionCondition { loop.pendingPermission?.id == id }
    }

    @MainActor
    private func waitForPermissionCondition(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(condition())
    }

    @Test @MainActor func overlappingPermissionWaitsKeepTheirOwnResponses() async throws {
        let loop = AgenticChatLoop(isBootstrap: false)
        let a = PermissionRequest(
            id: "a",
            toolName: "read_core",
            toolDisplayName: "Read",
            disclosure: nil
        )
        let b = PermissionRequest(
            id: "b",
            toolName: "read_core",
            toolDisplayName: "Read",
            disclosure: nil
        )
        let first = Task { await loop.requestPermission(a) }
        try await waitForPermission("a", in: loop)
        var secondStarted = false
        let second = Task {
            secondStarted = true
            return await loop.requestPermission(b)
        }
        try await waitForPermissionCondition { secondStarted }
        #expect(loop.pendingPermission?.id == "a")
        loop.resolvePermission(.allowOnce, requestID: "a")
        try await waitForPermission("b", in: loop)
        loop.resolvePermission(.deny, requestID: "a")
        #expect(loop.pendingPermission?.id == "b")
        loop.resolvePermission(.deny, requestID: "b")
        #expect(await first.value == .allowOnce)
        #expect(await second.value == .deny)
        #expect(loop.pendingPermission == nil)
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
            loop.resolvePermission(.allowOnce, requestID: "call_1")
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

    @Test @MainActor func localModelCannotActivateSkillsInline() {
        let activation = ActivateSkillTool().definition()
        let search = ToolDefinition(
            name: "search_knowledge",
            description: "Search",
            parameters: .init(type: "object")
        )
        #expect(LocalClient.makeBridgedTools([activation]).isEmpty)
        #expect(LocalClient.makeBridgedTools([search]).count == 1)
    }

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

        provider.baseURL = "local://test"
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

        loop.onToolsChanged = {
            Issue.record("Local inline execution must not refresh the batch registry")
            return (tools: [], executor: fakeToolExecutor)
        }

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
        let checkpoint = loop.buildCheckpoint()
        #expect(checkpoint.map(\.localID) == produced.map(\.localID))
        #expect(checkpoint.map(\.content) == produced.map(\.content))
        #expect(checkpoint.count { $0.toolCallID == "inline_1" } == 1)
    }

    @Test @MainActor func chunkedReplyMatchesDrainedPresentation() async throws {
        let (agent, provider, container) = try makeTestContext()
        _ = container
        let service = FakeChatService()
        service.enqueueEventStream([
            .contentDelta("Hello "), .contentDelta("🌍"), .contentDelta("!"), .finished(.stop),
        ])
        let loop = AgenticChatLoop(isBootstrap: false)
        let produced = try await loop.run(
            messages: [], tools: nil, agent: agent, provider: provider,
            chatService: service, toolExecutor: FakeToolExecutor()
        )
        #expect(produced.count == 1)
        #expect(produced.last?.content == "Hello 🌍!")
        #expect(produced.last?.content == loop.fullText)
        #expect(produced.last?.content == loop.displayedText)
    }

    @Test @MainActor func multipleInlineResultsRemainOrderedIncludingErrors() async throws {
        let (agent, provider, container) = try makeTestContext()
        _ = container
        let service = FakeChatService()
        let executor = FakeToolExecutor()
        let calls = ["inline_a", "inline_b"].map {
            ToolCall(id: $0, type: "function", function: .init(name: "read_core", arguments: "{}"))
        }
        service.enqueueInlineToolCalls(calls, after: [.contentDelta("Before. ")])
        executor.setResult(for: "inline_a", content: "failed", isError: true)
        executor.setResult(for: "inline_b", content: "success")
        service.enqueueEventStream([.contentDelta("Answer"), .finished(.stop)])
        let loop = AgenticChatLoop(isBootstrap: false, permissionPolicy: AlwaysAllowPolicy())
        let produced = try await loop.run(
            messages: [ChatMessage(role: "user", content: "Read")], tools: toolDefinitions,
            agent: agent, provider: provider, chatService: service, toolExecutor: executor
        )
        #expect(produced.map(\.role) == ["assistant", "tool", "assistant", "tool", "assistant"])
        #expect(produced[0].content == nil)
        #expect(produced[2].content == nil)
        #expect(produced[1].content == "failed")
        #expect(produced[3].content == "success")
        #expect(produced[4].content == "Before. Answer")
        #expect(produced[4].content == loop.fullText)
        #expect(produced[4].content == loop.displayedText)
        #expect(executor.calls.map(\.id) == calls.map(\.id))
        #expect(loop.roundsExecuted == 1)
    }

    @Test @MainActor func stopDuringReportingPrecedesMalformedBatchValidation() async throws {
        let (agent, provider, container) = try makeTestContext()
        _ = container
        let router = FakeModelRouter()
        Container.shared.modelRouter.register { router }
        defer { Container.shared.modelRouter.reset() }
        let loop = AgenticChatLoop(isBootstrap: false)
        await router.setRecordHook { await MainActor.run { _ = loop.stop() } }
        let service = FakeChatService()
        let executor = FakeToolExecutor()
        service.enqueueEventStream([
            .contentDelta("Partial"),
            .toolCall(.init(
                id: "bad",
                type: "function",
                function: .init(name: "read_core", arguments: "[]")
            )),
            .finished(.toolCalls),
        ])
        let produced = try await loop.run(
            messages: [],
            tools: nil,
            agent: agent,
            provider: provider,
            chatService: service,
            toolExecutor: executor
        )
        #expect(produced.isEmpty)
        #expect(executor.calls.isEmpty)
    }

    @Test @MainActor func inlineCheckpointExcludesExchangeUntilExecutionCompletes() async throws {
        let (agent, provider, container) = try makeTestContext()
        _ = container
        let loop = AgenticChatLoop(isBootstrap: false)
        let service = FakeChatService()
        let call = ToolCall(
            id: "inline_options",
            type: "function",
            function: .init(name: "present_options", arguments: "{}")
        )
        service.enqueueInlineToolCalls([call])
        service.enqueueEventStream([.contentDelta("Done"), .finished(.stop)])
        let (entered, signal) = AsyncStream<Void>.makeStream()
        let executor = SuspendedOptionsExecutor { _ in
            signal.yield(())
            _ = await loop.presentOptions(OptionSet(id: call.id, question: nil, options: []))
        }
        let task = Task {
            try await loop.run(
                messages: [],
                tools: nil,
                agent: agent,
                provider: provider,
                chatService: service,
                toolExecutor: executor
            )
        }
        for await _ in entered {
            break
        }
        #expect(loop.buildCheckpoint().isEmpty)
        loop.resolveOptions(.selected(label: "Continue"))
        let produced = try await task.value
        #expect(produced.map(\.role) == ["assistant", "tool", "assistant"])
        #expect(produced[1].toolCallID == call.id)
        #expect(produced.last?.content == "Done")
    }

    @Test @MainActor func toolRefreshReachesNextRequestAndExecutor() async throws {
        let (agent, provider, container) = try makeTestContext()
        _ = container
        let service = FakeChatService()
        let original = FakeToolExecutor()
        let refreshed = FakeToolExecutor()
        let calls = ["activate", "new_tool"].map {
            ToolCall(id: $0, type: "function", function: .init(name: "read_core", arguments: "{}"))
        }
        service.enqueueEventStreams([
            [
                .contentDelta("Checking"),
                .providerMetadata(["signature": "first"]),
                .providerMetadata(["signature": "last"]),
                .toolCall(calls[0]),
                .finished(.toolCalls),
            ],
            [.toolCall(calls[1]), .finished(.toolCalls)],
            [.contentDelta("Done"), .providerMetadata(["final": "omitted"]), .finished(.stop)],
        ])
        let definitions = toolDefinitions
        let updated = Array(definitions.prefix(1))
        let loop = AgenticChatLoop(isBootstrap: false, permissionPolicy: AlwaysAllowPolicy())
        loop.onToolsChanged = { (tools: updated, executor: refreshed) }
        let produced = try await loop.run(
            messages: [ChatMessage(role: "user", content: "Activate")], tools: definitions,
            agent: agent, provider: provider, chatService: service, toolExecutor: original
        )
        #expect(original.calls.map(\.id) == ["activate"])
        #expect(refreshed.calls.map(\.id) == ["new_tool"])
        #expect(service.capturedEventTools?.map { $0.function.name } == updated
            .map { $0.function.name })
        #expect(produced[0].providerMetadata == ["signature": "last"])
        #expect(produced.last?.providerMetadata == nil)
        #expect(service.capturedEventMessages.contains { $0.toolCallID == "new_tool" })
        #expect(produced.last?.content == "Done")
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

private struct SuspendedOptionsExecutor: ToolExecutor {
    let executeOptions: @MainActor @Sendable (ToolCall) async -> Void

    func executionMode(for toolName: String) -> ToolExecutionMode {
        .interactive
    }

    @MainActor func execute(_ toolCall: ToolCall, agent: Agent) async -> ToolResult {
        await executeOptions(toolCall)
        return ToolResult(toolCallID: toolCall.id, content: "Dismissed", isError: false)
    }
}
