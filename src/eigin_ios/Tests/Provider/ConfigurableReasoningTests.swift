@testable import Eigin
import Foundation
import os
import Testing

@Suite("Configurable reasoning")
struct ConfigurableReasoningTests {
    private let large = "mistral-large-4-0"
    private let medium = "mistral-medium-3-5"

    private func provider(
        _ baseURL: String = "https://api.mistral.ai/v1",
        includeMedium: Bool = false
    ) -> RoutingProvider {
        RoutingProvider(
            id: UUID(), name: "Mistral", baseURL: baseURL,
            availableModels: [large, "mistral-small-2506"] + (includeMedium ? [medium] : [])
        )
    }

    private func request(
        _ provider: RoutingProvider, conversation: UUID, text: String = "Hello",
        model: String = "mistral-large-4-0", isAuto: Bool = true
    ) -> RouteRequest {
        RouteRequest(
            currentProviderID: provider.id, currentModel: model, isAuto: isAuto,
            requirements: RouteRequirements(), providers: [provider],
            conversationID: conversation, lastUserMessage: text
        )
    }

    private func router() -> DefaultModelRouter {
        DefaultModelRouter(reachability: FakeNetworkReachability(), localModelReadiness: { false })
    }

    private func resolve(
        _ router: DefaultModelRouter, _ request: RouteRequest
    ) async -> (model: String, reasoningEffort: ReasoningEffort?) {
        let route = await router.resolve(request)
        return await (route.model, router.reasoningEffort(for: route.model, request: request))
    }

    @Test(arguments: [0, 1, 2, 3, 4])
    func earlyTurnsRequireStrongComplexity(depth: Int) async {
        let provider = provider()
        let request = RouteRequest(
            currentProviderID: provider.id, currentModel: large, isAuto: true,
            requirements: RouteRequirements(), providers: [provider], conversationID: UUID(),
            lastUserMessage: "Analyze and compare trade-offs step by step. Explain why.",
            turnContext: RoutingTurnContext(responseTurnCount: depth)
        )
        let result = await resolve(router(), request)
        #expect(result.model == large)
        #expect(result.reasoningEffort == (depth < 4 ? .low : .medium))
    }

    @Test(arguments: [0, 1, 2, 3, 4])
    func technicalRequestsGainReasoningGradually(depth: Int) async {
        let provider = provider()
        let request = RouteRequest(
            currentProviderID: provider.id, currentModel: large, isAuto: true,
            requirements: RouteRequirements(), providers: [provider], conversationID: UUID(),
            lastUserMessage: "```swift func solve() {} ``` Explain the algorithm and database.",
            turnContext: RoutingTurnContext(responseTurnCount: depth)
        )
        let result = await resolve(router(), request)
        #expect(result.reasoningEffort == (depth < 2 ? .low : .medium))
    }

    @Test func clearlyDifficultFirstRequestCanEscalate() async {
        let provider = provider()
        let text = "Analyze this algorithm and compare the database trade-offs step by step. Explain why. ```swift func solve() {} ```"
        #expect(QueryComplexity.score(text: text) >= 0.70)
        let request = RouteRequest(
            currentProviderID: provider.id, currentModel: large, isAuto: true,
            requirements: RouteRequirements(), providers: [provider], conversationID: UUID(),
            lastUserMessage: text, turnContext: RoutingTurnContext(responseTurnCount: 0)
        )
        let result = await resolve(router(), request)
        #expect(result.reasoningEffort == .medium)
    }

    @Test func agentStartedChatUsesFastDemand() async {
        let provider = provider()
        let request = RouteRequest(
            currentProviderID: provider.id, currentModel: large, isAuto: true,
            requirements: RouteRequirements(), providers: [provider], conversationID: UUID(),
            turnContext: RoutingTurnContext(responseTurnCount: 0)
        )
        let router = router()
        let result = await resolve(router, request)
        #expect(result.reasoningEffort == .low)
        #expect(await router.reasoningEffort(for: large, request: request) == .low)
    }

    @Test func depthExcludesToolsAndSummaries() {
        let tool = ToolCall(
            id: "call",
            type: "function",
            function: .init(name: "search", arguments: "{}")
        )
        var summary = ChatMessage(role: "assistant", content: "Summary")
        summary.isCompactionSummary = true
        let history = [
            ChatMessage(role: "user", content: "Question"),
            ChatMessage(role: "assistant", content: "Searching", toolCalls: [tool]),
            ChatMessage(role: "tool", content: "Result"),
            ChatMessage(role: "assistant", content: "Answer"),
            ChatMessage(role: "assistant", content: ""), summary,
        ]
        #expect(RoutingTurnContext(messages: history).responseTurnCount == 1)
    }

    @Test(arguments: [false, true])
    func recoveryFragmentsKeepNextExchangeConservative(recovered: Bool) async {
        let provider = provider()
        var history = [
            ChatMessage(role: "user", content: "First"),
            ChatMessage(role: "assistant", content: "Partial"),
        ]
        if recovered { history.append(ChatMessage(role: "assistant", content: "Completed answer")) }
        let text = "Analyze and compare trade-offs step by step. Explain why."
        history.append(ChatMessage(role: "user", content: text))
        let request = RouteRequest(
            currentProviderID: provider.id, currentModel: large, isAuto: true,
            requirements: RouteRequirements(), providers: [provider], conversationID: UUID(),
            lastUserMessage: text, turnContext: RoutingTurnContext(messages: history)
        )
        let result = await resolve(router(), request)
        #expect(result.reasoningEffort == .low)
    }

    @Test func preferredModelStartsLowAndEscalatesWithoutSwitching() async {
        let router = router()
        let provider = provider()
        let conversation = UUID()
        let first = await resolve(router, request(provider, conversation: conversation))
        #expect(first.model == large)
        #expect(first.reasoningEffort == .low)
        let complex = await resolve(router, request(
            provider, conversation: conversation,
            text: "Analyze the trade-offs and compare alternatives step by step. Explain why."
        ))
        #expect(complex.model == large)
        #expect(complex.reasoningEffort == .medium)
        let followup = await resolve(router, request(provider, conversation: conversation))
        #expect(followup.reasoningEffort == .medium)
        let separate = await resolve(router, request(provider, conversation: UUID()))
        #expect(separate.reasoningEffort == .low)
    }

    @Test func catalogPreferenceIsPreservedAcrossEfforts() async {
        let provider = provider(includeMedium: true)
        let router = router()
        let conversation = UUID()
        let first = await resolve(router, request(provider, conversation: conversation))
        #expect(first.model == large)
        #expect(first.reasoningEffort == .low)
        let next = await resolve(router, request(
            provider, conversation: conversation,
            text: "Analyze and compare trade-offs step by step. Explain why.", model: first.model
        ))
        #expect(next.model == large)
        #expect(next.reasoningEffort == .medium)
    }

    @Test func idleResetReturnsToLowestEffort() async {
        let clock = OSAllocatedUnfairLock(initialState: Date(timeIntervalSince1970: 0))
        let router = DefaultModelRouter(
            reachability: FakeNetworkReachability(), localModelReadiness: { false },
            now: { clock.withLock { $0 } }
        )
        let provider = provider()
        let conversation = UUID()
        let escalated = await resolve(router, request(
            provider, conversation: conversation,
            text: "Analyze and compare trade-offs step by step. Explain why."
        ))
        #expect(escalated.reasoningEffort == .medium)
        clock.withLock { $0 = $0.addingTimeInterval(3601) }
        let reset = await resolve(router, request(provider, conversation: conversation))
        #expect(reset.reasoningEffort == .low)
    }

    @Test func complexRequestWithoutDepthUsesMedium() async {
        let provider = provider()
        let route = await resolve(router(), request(
            provider, conversation: UUID(),
            text: "Analyze and compare trade-offs step by step. Explain why."
        ))
        #expect(route.model == large)
        #expect(route.reasoningEffort == .medium)
    }

    @Test func pinnedModelsOmitEffort() async {
        let provider = provider()
        let route = await resolve(router(), request(provider, conversation: UUID(), isAuto: false))
        #expect(route.model == large)
        #expect(route.reasoningEffort == nil)
    }

    @Test func unverifiedEndpointsOmitEffort() async {
        let provider = provider("https://custom.example/v1")
        let route = await resolve(router(), request(provider, conversation: UUID()))
        #expect(route.reasoningEffort == nil)
    }

    @Test func hedgeRecomputesLowestEffortForCandidate() async throws {
        let router = router()
        let provider = provider(includeMedium: true)
        let conversation = UUID()
        let initial = await resolve(router, request(provider, conversation: conversation))
        let request = request(provider, conversation: conversation, model: initial.model)
        let hedge = try #require(await router.hedgeCandidate(
            after: initial.model,
            request: request
        ))
        #expect(hedge.model == medium)
        #expect(await router.reasoningEffort(for: hedge.model, request: request) == ReasoningEffort
            .none)
    }

    @Test func retryKeepsLowDemandForConfigurableModels() async throws {
        let router = router()
        let provider = provider(includeMedium: true)
        let conversation = UUID()
        let initial = await resolve(router, request(provider, conversation: conversation))
        let request = request(provider, conversation: conversation, model: initial.model)
        let next = try #require(await router.retry(
            after: OpenAICompatibleClientError.httpError(503, body: nil), request: request
        ))
        #expect(next.model == medium)
        #expect(await router.reasoningEffort(for: next.model, request: request) == ReasoningEffort
            .none)
    }

    @Test(arguments: ["mistral/mistral-large-4-0", "mistral-large-4-0", "mistral-large-4"])
    func relayPrefersLargeAtLowThenMedium(model: String) async {
        let provider = RoutingProvider(
            id: UUID(), name: "Relay", baseURL: ProviderPreset.relayBaseURL,
            availableModels: ["corti/corti-s1-instant", "corti/corti-s1", model]
        )
        let router = router()
        let conversation = UUID()
        let first = await resolve(router, request(
            provider, conversation: conversation, model: "corti/corti-s1-instant"
        ))
        #expect(first.model == model)
        #expect(first.reasoningEffort == .low)
        let next = await resolve(router, request(
            provider, conversation: conversation,
            text: "Analyze and compare trade-offs step by step. Explain why.", model: first.model
        ))
        #expect(next.model == model)
        #expect(next.reasoningEffort == .medium)
    }

    @Test func relayMediumUsesNoneInsteadOfLow() async {
        let model = "mistral/mistral-medium-2604"
        let provider = RoutingProvider(
            id: UUID(), name: "Relay", baseURL: ProviderPreset.relayBaseURL,
            availableModels: [model]
        )
        let route = await resolve(router(), request(provider, conversation: UUID(), model: model))
        #expect(route.reasoningEffort == ReasoningEffort.none)
    }
}
