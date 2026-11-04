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
        #expect(complex.reasoningEffort == .high)
        let followup = await resolve(router, request(provider, conversation: conversation))
        #expect(followup.reasoningEffort == .high)
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
        #expect(next.reasoningEffort == .high)
    }

    @Test func idleResetReturnsToLowestEffort() async {
        let clock = OSAllocatedUnfairLock(initialState: Date(timeIntervalSince1970: 0))
        let router = DefaultModelRouter(
            reachability: FakeNetworkReachability(), localModelReadiness: { false },
            now: { clock.withLock { $0 } }
        )
        let provider = provider()
        let conversation = UUID()
        let high = await resolve(router, request(
            provider, conversation: conversation,
            text: "Analyze and compare trade-offs step by step. Explain why."
        ))
        #expect(high.reasoningEffort == .high)
        clock.withLock { $0 = $0.addingTimeInterval(3601) }
        let reset = await resolve(router, request(provider, conversation: conversation))
        #expect(reset.reasoningEffort == .low)
    }

    @Test func complexFirstTurnStartsHigh() async {
        let provider = provider()
        let route = await resolve(router(), request(
            provider, conversation: UUID(),
            text: "Analyze and compare trade-offs step by step. Explain why."
        ))
        #expect(route.model == large)
        #expect(route.reasoningEffort == .high)
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
    func relayPrefersLargeAtLowThenHigh(model: String) async {
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
        #expect(next.reasoningEffort == .high)
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
