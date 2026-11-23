import EiginSDK
import Testing

@Suite("Routing bindings")
struct RoutingTests {
    private typealias Routing = EiginSDK.Experimental.Routing

    private func request(conversation: String? = nil) -> Routing.Request {
        Routing.Request(
            providerId: "provider", currentModel: "gpt-4.1", automatic: true,
            conversationId: conversation, messageNeedsReasoning: false,
            requirements: Routing.Requirements(needsTools: true, needsVision: false, promptTokens: nil),
            inventory: Routing.Inventory(
                providerId: "provider", baseUrl: "https://provider.test/v1",
                available: ["gpt-4.1", "gpt-4.1-mini"], enabled: [], models: []
            )
        )
    }

    @Test func stateSurvivesCallsAndInitialization() async throws {
        let router = Routing.Router.withCatalog()
        let input = request(conversation: "conversation")
        #expect(router.resolve(request: input, now: 0, decisionTime: 0).model == "gpt-4.1")
        let replacement = try #require(router.replacement(request: input, failure: .modelNotFound, reasoningDemand: nil, now: 1, decisionTime: 1))
        #expect(replacement.model == "gpt-4.1-mini")
        #expect(replacement.change == .modelRetired(previous: "gpt-4.1"))
        try await EiginSDK.initialize()
        #expect(router.resolve(request: input, now: 2, decisionTime: 2).model == "gpt-4.1-mini")
        #expect(Routing.Router.withCatalog().resolve(request: input, now: 2, decisionTime: 2).model == "gpt-4.1")
    }

    @Test func optionalReplacementAndHealthTimesCrossBindings() {
        let router = Routing.Router.withCatalog()
        let input = request()
        router.record(
            outcome: Routing.Outcome(
                providerId: "provider", model: "gpt-4.1-mini", firstTokenSeconds: nil,
                tokensPerSecond: nil, result: .failed(failure: .timedOut)
            ), now: 0
        )
        #expect(router.replacement(
            request: input, failure: .preAnswerBufferLimit, reasoningDemand: nil,
            now: 299.999, decisionTime: 299.999
        ) == nil)
        #expect(router.replacement(
            request: input, failure: .preAnswerBufferLimit, reasoningDemand: nil,
            now: 300, decisionTime: 300
        )?.model == "gpt-4.1-mini")
        router.recordHedgeLoss(model: "gpt-4.1", now: 301)
        #expect(router.hedgeDelay(model: "gpt-4.1") == 6)
    }
}
