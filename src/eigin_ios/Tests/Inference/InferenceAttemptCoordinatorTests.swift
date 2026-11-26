@testable import Eigin
import Foundation
import os
import Testing

@Suite("Inference attempt coordination")
@MainActor
struct InferenceAttemptCoordinatorTests {
    @Test(arguments: ["same-model", "retry", "hedge"], [false, true])
    @MainActor func dispatchesSessionEffortAcrossTurnsAndFallbacks(
        mode: String,
        early: Bool
    ) async throws {
        let provider = Provider(name: "Test", baseURL: "https://api.mistral.ai/v1")
        provider.availableModels = mode == "same-model"
            ? ["mistral-large-4-0"] : ["mistral-medium-3-5", "mistral-large-4-0"]
        let router = DefaultModelRouter(
            reachability: FakeNetworkReachability(), localModelReadiness: { false }
        )

        let conversation = UUID()
        let routingProvider = RoutingProvider(
            id: provider.id, name: provider.name, baseURL: provider.baseURL,
            availableModels: provider.availableModels
        )
        let service = ObservedChatService { _, _, _ in }
        let calls = OSAllocatedUnfairLock(initialState: [(String, ReasoningEffort?)]())
        service.observeEffort = { model, effort in calls.withLock { $0.append((model, effort)) } }
        var model = "test-model"
        let texts = ["Hello", "Analyze and compare trade-offs step by step. Explain why.", "Thanks"]
        var firstModel = ""
        for (index, text) in texts.enumerated() {
            let request = RouteRequest(
                currentProviderID: provider.id, currentModel: model, isAuto: true,
                requirements: RouteRequirements(), providers: [routingProvider],
                conversationID: conversation, lastUserMessage: text,
                turnContext: early ? RoutingTurnContext(responseTurnCount: 0) : nil
            )
            let route = await router.resolve(request)
            model = route.model
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
            let stream = try await InferenceAttemptCoordinator(modelRouter: router).open(
                chatService: service, host: provider.baseURL, hostID: provider.id, model: model,
                messages: [ChatMessage(role: "user", content: text)], tools: nil,
                cacheKey: nil, routing: { request.forPreparedTurn(model: model, requirements: $0) }
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

    @Test func localDispatchForwardsTheInlineRunnerWithoutRouting() async throws {
        let service = FakeChatService()
        let call = ToolCall(
            id: "1",
            type: "function",
            function: .init(name: "read", arguments: "{}")
        )
        service.enqueueInlineToolCalls([call])
        service.enqueueEventStream([.contentDelta("done"), .finished(.stop)])
        var calls: [ToolCall] = []
        let runner = InlineToolRunner { call in
            calls.append(call)
            return ToolResult(toolCallID: call.id, content: "ok", isError: false)
        }
        let attempt = try await InferenceAttemptCoordinator(modelRouter: FakeModelRouter()).open(
            chatService: service, host: "local://test", hostID: UUID(), model: "local-model",
            messages: [], tools: nil, cacheKey: "key",
            inlineToolRunner: runner,
            routing: { _ in Issue.record("Local dispatch requested routing"); return nil }
        )
        for try await _ in attempt.stream {}
        #expect(calls == [call])
        #expect(service.lastModel == "local-model")
        #expect(service.capturedEventCacheKey == "key")
    }

    @Test func localFailuresSurfaceAtDispatchOrDuringIteration() async throws {
        let coordinator = InferenceAttemptCoordinator(modelRouter: FakeModelRouter())
        let service = FakeChatService()
        let error = OpenAICompatibleClientError.httpError(503, body: nil)
        func open() async throws -> InferenceAttempt {
            try await coordinator.open(
                chatService: service,
                host: "local://test",
                hostID: UUID(),
                model: "local-model",
                messages: [],
                tools: nil,
                cacheKey: nil,
                routing: { _ in nil }
            )
        }
        service.throwOnEventStream(error)
        await #expect(throws: OpenAICompatibleClientError.self) { try await open() }
        service.enqueueEventStream([], endingWith: error)
        let attempt = try await open()
        await #expect(throws: OpenAICompatibleClientError.self) {
            for try await _ in attempt.stream {}
        }
    }

    @Test(arguments: [false, true])
    func preOutputFailuresRespectRoutingAndSwitchBudget(routed: Bool) async throws {
        let router = DefaultModelRouter(
            reachability: FakeNetworkReachability(),
            localModelReadiness: { false }
        )
        let service = FakeChatService()
        let failure = OpenAICompatibleClientError.httpError(
            404,
            body: "The model `retired-model` does not exist"
        )
        for _ in 0 ..< 3 {
            service.enqueueEventStream([], endingWith: failure)
        }
        let id = UUID(), host = "https://fake.local"
        let original = RoutingProvider(id: id, name: "Test", baseURL: host, availableModels: ["a"])
        let updated = RoutingProvider(
            id: id,
            name: "Test",
            baseURL: host,
            availableModels: ["gpt-4.1", "gpt-4.1-mini", "gpt-4.1-nano"]
        )
        var refreshes: [UUID] = []
        let attempt = try await InferenceAttemptCoordinator(modelRouter: router).open(
            chatService: service, host: host, hostID: id, model: "a", messages: [], tools: nil,
            cacheKey: nil,
            routing: { routed ? RouteRequest(
                currentProviderID: id,
                currentModel: "a",
                isAuto: true,
                requirements: $0,
                providers: [original]
            ) : nil },
            refreshCatalog: { id in refreshes.append(id); return updated }
        )
        await #expect(throws: OpenAICompatibleClientError.self) {
            for try await _ in attempt.stream {}
        }
        let report = await attempt.report(sentAt: nil, result: .failed(.modelNotFound))
        #expect(report == nil)
        #expect(service.lastModel == (routed ? "gpt-4.1-mini" : "a"))
        #expect(refreshes == (routed ? [id] : []))
    }

    @Test func hedgeWinnerPreservesSelectionWithoutRetry() async throws {
        let router = DefaultModelRouter(
            reachability: FakeNetworkReachability(),
            localModelReadiness: { false }
        )
        let service = FakeChatService(), id = UUID()
        service.delayBeforeStream(.seconds(60), for: "gpt-4.1")
        service.enqueueEventStream([.contentDelta("fallback answer"), .finished(.stop)])
        let attempt = try await InferenceAttemptCoordinator(modelRouter: router).open(
            chatService: service, host: "https://fake.local", hostID: id, model: "gpt-4.1",
            messages: [], tools: nil, cacheKey: nil,
            routing: { RouteRequest(
                currentProviderID: id,
                currentModel: "gpt-4.1",
                isAuto: true,
                requirements: $0,
                providers: [RoutingProvider(
                    id: id,
                    name: "Test",
                    baseURL: "https://fake.local",
                    availableModels: ["gpt-4.1", "gpt-4.1-mini"]
                )]
            ) }
        )
        var events: [ChatStreamEvent] = []
        for try await event in attempt.stream {
            events.append(event)
        }
        #expect(events == [.contentDelta("fallback answer"), .finished(.stop)])
        #expect(try attempt.winningModel == "gpt-4.1-mini")
        #expect(try !attempt.retryWon)
        #expect(service.lastModel == "gpt-4.1-mini")
    }
}
