@testable import Eigin
import Foundation
import os
import Testing

@Suite("DefaultModelRouter")
struct ModelRouterTests {
    // MARK: - Fixtures

    /// Ranked best-first in ``KnownModelCatalog``. All support tools and vision.
    static let best = "claude-sonnet-5"
    static let second = "gpt-5.6"
    static let third = "gemini-3.5-flash"
    /// Supports tools but not vision, and ranks below the three above.
    static let sightless = "glm-5.2"
    /// The on-device model: small context, no vision.
    static let onDevice = "gemma-4-e2b"

    private let cloudID = UUID()
    private let localID = UUID()

    private func cloud(_ models: [String]? = nil, enabled: [String] = []) -> RoutingProvider {
        RoutingProvider(
            id: cloudID,
            name: "Test Cloud",
            baseURL: "https://cloud.test/v1",
            availableModels: models ?? [Self.best, Self.second, Self.third, Self.sightless],
            enabledModels: enabled
        )
    }

    private func local() -> RoutingProvider {
        RoutingProvider(
            id: localID,
            name: "On device",
            baseURL: "local://",
            availableModels: [Self.onDevice]
        )
    }

    private func request(
        model: String,
        isAuto: Bool = true,
        requirements: RouteRequirements = RouteRequirements(),
        providers: [RoutingProvider]? = nil
    ) -> RouteRequest {
        RouteRequest(
            currentProviderID: cloudID,
            currentModel: model,
            isAuto: isAuto,
            requirements: requirements,
            providers: providers ?? [cloud()]
        )
    }

    /// A clock the test advances by hand.
    private final class TestClock: @unchecked Sendable {
        private let state = OSAllocatedUnfairLock(initialState: Date(timeIntervalSince1970: 0))
        var now: Date {
            state.withLock { $0 }
        }

        func advance(_ interval: TimeInterval) {
            state.withLock { $0 = $0.addingTimeInterval(interval) }
        }
    }

    private func makeRouter(
        reachability: FakeNetworkReachability = FakeNetworkReachability(),
        localReady: Bool = true,
        clock: TestClock = TestClock()
    ) -> DefaultModelRouter {
        DefaultModelRouter(
            reachability: reachability,
            localModelReadiness: { localReady },
            now: { clock.now }
        )
    }

    private func failure(_ code: Int, body: String? = nil) -> Error {
        OpenAICompatibleClientError.httpError(code, body: body)
    }

    private var modelNotFound: Error {
        OpenAICompatibleClientError.httpError(404, body: "the model does not exist")
    }

    // MARK: - Auto off

    @Test("a pinned model is never routed away from")
    func pinnedModelIsLeftAlone() async {
        let router = makeRouter()
        let pinned = request(model: Self.sightless, isAuto: false)

        let route = await router.resolve(pinned)
        #expect(route.model == Self.sightless)
        #expect(route.change == nil)

        await router.record(outcome(model: Self.sightless, result: .failed(.providerOverloaded)))
        #expect(await router.retry(after: failure(503), request: pinned) == nil)
        #expect(await router.resolve(pinned).model == Self.sightless)
    }

    // MARK: - Stickiness

    @Test("a healthy model keeps the turn even when something ranks higher")
    func staysOnHealthyModel() async {
        let router = makeRouter()
        let onSecondBest = request(model: Self.second)

        let route = await router.resolve(onSecondBest)
        #expect(route.model == Self.second)
        #expect(route.change == nil)
    }

    // MARK: - Retirement

    @Test("a retired model is replaced, and exhausting the catalog surfaces the error")
    func retiredModelWalksDownTheRanking() async throws {
        let router = makeRouter()
        var current = Self.best
        var seen = [current]

        for _ in 0 ..< 3 {
            let next = try #require(
                await router.retry(after: modelNotFound, request: request(model: current))
            )
            #expect(!seen.contains(next.model))
            current = next.model
            seen.append(current)
        }

        // Every known candidate is now retired.
        #expect(await router.retry(after: modelNotFound, request: request(model: current)) == nil)
    }

    @Test("a retired model is reported as retired, not degraded")
    func retirementIsDistinguishedFromDegradation() async {
        let router = makeRouter()
        let next = await router.retry(after: modelNotFound, request: request(model: Self.best))
        #expect(next?.change == .modelRetired(previous: Self.best))
    }

    // MARK: - Not the model's fault

    @Test(
        "auth, credit, and malformed-request failures surface instead of burning another model",
        arguments: [401, 402, 403, 400]
    )
    func userFixableFailuresAreNotRoutedAround(code: Int) async {
        let router = makeRouter()
        let onBest = request(model: Self.best)

        #expect(await router.retry(after: failure(code), request: onBest) == nil)
        // Health is untouched, so the model is still the one chosen.
        #expect(await router.resolve(onBest).model == Self.best)
    }

    @Test("an empty wallet is never blamed on the model")
    func creditsErrorIsNotTheModelsFault() async {
        let router = makeRouter()
        let error = CreditsError.noCreditsRemaining
        #expect(await router.retry(after: error, request: request(model: Self.best)) == nil)
    }

    // MARK: - Overload

    @Test("an overloaded model steps aside, and comes back once its quarantine expires")
    func overloadQuarantineExpires() async {
        let clock = TestClock()
        let router = makeRouter(clock: clock)

        let next = await router.retry(after: failure(503), request: request(model: Self.best))
        #expect(next?.model == Self.second)
        #expect(next?.change == .modelDegraded(previous: Self.best, reason: .errors))

        // Still quarantined a minute later.
        clock.advance(60)
        #expect(await router.resolve(request(model: Self.best)).model != Self.best)

        // Free again after the quarantine, and preferred once more.
        clock.advance(10 * 60)
        #expect(await router.resolve(request(model: Self.best)).model == Self.best)
    }

    // MARK: - Session decay

    @Test("an idle hour clears health and climbs back to the preferred model")
    func sessionResetClimbsBack() async {
        let clock = TestClock()
        let router = makeRouter(clock: clock)

        // Work down the list until the agent is on a much worse model.
        var current = Self.best
        for _ in 0 ..< 3 {
            guard let next = await router.retry(
                after: failure(503), request: request(model: current)
            ) else { break }
            current = next.model
        }
        #expect(current != Self.best)

        clock.advance(61 * 60)
        let route = await router.resolve(request(model: current))
        #expect(route.model == Self.best)
        #expect(route.change == .sessionReset(previous: current))
    }

    @Test("within the hour, a demoted model is not restored")
    func sessionDoesNotResetTooEarly() async {
        let clock = TestClock()
        let router = makeRouter(clock: clock)

        let next = await router.retry(after: failure(503), request: request(model: Self.best))
        let demoted = try? #require(next?.model)

        clock.advance(30 * 60)
        #expect(await router.resolve(request(model: demoted ?? "")).model != Self.best)
    }

    // MARK: - Requirements

    @Test("a turn with images prefers a model that can see them")
    func visionIsPreferred() async {
        let router = makeRouter()
        let sightlessOnly = cloud([Self.sightless, Self.third])
        let route = await router.resolve(
            request(
                model: Self.sightless,
                requirements: RouteRequirements(needsVision: true),
                providers: [sightlessOnly]
            )
        )
        #expect(route.model == Self.third)
    }

    @Test("a provider with no vision model still answers, with the images stripped downstream")
    func visionRelaxesRatherThanFailing() async {
        let router = makeRouter()
        let noVision = cloud([Self.sightless])
        let route = await router.resolve(
            request(
                model: Self.sightless,
                requirements: RouteRequirements(needsVision: true),
                providers: [noVision]
            )
        )
        #expect(route.model == Self.sightless)
    }

    @Test("a retry never drops to a model too small for the prompt already built")
    func retryRespectsMeasuredContextWindow() async {
        let router = makeRouter()
        // The on-device model is the only alternative, and its window is far too small.
        let mixed = RoutingProvider(
            id: cloudID,
            name: "Test Cloud",
            baseURL: "https://cloud.test/v1",
            availableModels: [Self.best, Self.onDevice]
        )
        let bigPrompt = request(
            model: Self.best,
            requirements: RouteRequirements(promptTokens: 200_000),
            providers: [mixed]
        )
        #expect(await router.retry(after: failure(503), request: bigPrompt) == nil)
    }

    @Test("a small prompt can fall back to a small model")
    func retryAllowsSmallModelForSmallPrompt() async {
        let router = makeRouter()
        let mixed = RoutingProvider(
            id: cloudID,
            name: "Test Cloud",
            baseURL: "https://cloud.test/v1",
            availableModels: [Self.best, Self.onDevice]
        )
        let smallPrompt = request(
            model: Self.best,
            requirements: RouteRequirements(promptTokens: 4000),
            providers: [mixed]
        )
        let next = await router.retry(after: failure(503), request: smallPrompt)
        #expect(next?.model == Self.onDevice)
    }

    @Test("an unrecognised catalog leaves the agent where it is")
    func unknownCatalogStaysPut() async {
        let router = makeRouter()
        let unknown = cloud(["vendor/mystery-model-1", "vendor/mystery-model-2"])
        let route = await router.resolve(
            request(model: "vendor/mystery-model-1", providers: [unknown])
        )
        #expect(route.model == "vendor/mystery-model-1")
        #expect(route.change == nil)
    }

    // MARK: - Enabled models

    @Test("Auto routing skips a model the user disabled")
    func disabledModelIsSkipped() async {
        let router = makeRouter()
        // Only `second` is enabled; `best` ranks higher but is switched off.
        let provider = cloud(enabled: [Self.second])
        let route = await router.resolve(request(model: Self.best, providers: [provider]))
        #expect(route.model == Self.second)
        #expect(route.model != Self.best)
    }

    @Test(
        "a disabled model is not reinstated when every enabled one is quarantined"
    )
    func disabledModelIsNotReinstatedViaQuarantine() async {
        let clock = TestClock()
        let router = makeRouter(clock: clock)
        let provider = cloud(enabled: [Self.second])

        // Quarantine the only enabled model. `best` is healthy and still served, but the
        // user turned it off, so the quarantine fallback must not reach for it.
        _ = await router.retry(
            after: failure(503), request: request(model: Self.second, providers: [provider])
        )
        clock.advance(60)

        let route = await router.resolve(
            request(model: Self.second, providers: [provider])
        )
        // Stays on the quarantined enabled model rather than the disabled `best`.
        #expect(route.model == Self.second)
        #expect(route.model != Self.best)
    }

    @Test(
        "a provider with no models enabled falls back to the full catalogue"
    )
    func emptyEnablementFallsBackToFullCatalogue() async {
        let router = makeRouter()
        // Empty enablement: a legacy provider seeded before the field existed. The full
        // fetched catalogue is the offer, so `best` is selectable.
        let provider = cloud([Self.best, Self.second], enabled: [])
        // Drive a switch off `second` so the resolve can land on `best`. A fresh
        // `resolve` alone would not: the first turn sets the session clock without a
        // reset, so stickiness keeps the agent on the healthy `second`.
        _ = await router.retry(
            after: failure(503), request: request(model: Self.second, providers: [provider])
        )
        let route = await router.resolve(
            request(model: Self.second, providers: [provider])
        )
        #expect(route.model == Self.best)
    }

    @Test("the offline fallback takes the enabled on-device model, not the first served")
    func offlineFallbackRespectsEnabledLocal() async {
        let router = makeRouter(reachability: FakeNetworkReachability(isReachable: false))
        let preferred = "local/experimental"
        let local = RoutingProvider(
            id: localID,
            name: "On device",
            baseURL: "local://",
            availableModels: [Self.onDevice, preferred],
            enabledModels: [preferred]
        )
        let route = await router.resolve(
            request(model: Self.best, providers: [cloud(), local])
        )
        #expect(route.providerID == localID)
        #expect(route.model == preferred)
        #expect(route.model != Self.onDevice)
    }

    @Test("a model kept enabled but retired from the catalogue is not chosen")
    func staleEnabledModelIsNotChosen() async {
        let router = makeRouter()
        // `best` is still switched on, but the provider no longer serves it; `second`
        // is what remains. Without intersecting enabled against available, Auto would
        // stay on the dead `best`.
        let provider = cloud([Self.second], enabled: [Self.best, Self.second])
        let route = await router.resolve(request(model: Self.best, providers: [provider]))
        #expect(route.model == Self.second)
        #expect(route.model != Self.best)
    }

    // MARK: - canSatisfy

    @Test("the vision question is asked of the whole catalog, not the current model")
    func canSatisfyReflectsTheCatalog() async {
        let router = makeRouter()
        let visionRequirements = RouteRequirements(needsVision: true)

        // Currently on a sightless model, but the provider has models that can see.
        #expect(
            await router.canSatisfy(
                request(model: Self.sightless, requirements: visionRequirements)
            )
        )

        #expect(
            await router.canSatisfy(
                request(
                    model: Self.sightless,
                    requirements: visionRequirements,
                    providers: [cloud([Self.sightless])]
                )
            ) == false
        )
    }

    @Test("quarantining the last vision model closes the door")
    func canSatisfyFollowsHealth() async {
        let router = makeRouter()
        let oneVisionModel = cloud([Self.sightless, Self.third])
        let visionRequirements = RouteRequirements(needsVision: true)

        #expect(
            await router.canSatisfy(
                request(
                    model: Self.third, requirements: visionRequirements,
                    providers: [oneVisionModel]
                )
            )
        )

        _ = await router.retry(
            after: modelNotFound,
            request: request(model: Self.third, providers: [oneVisionModel])
        )

        #expect(
            await router.canSatisfy(
                request(
                    model: Self.sightless, requirements: visionRequirements,
                    providers: [oneVisionModel]
                )
            ) == false
        )
    }

    // MARK: - Offline

    @Test("an unreachable network routes to the on-device model")
    func offlineRoutesToLocal() async {
        let router = makeRouter(reachability: FakeNetworkReachability(isReachable: false))
        let route = await router.resolve(
            request(model: Self.best, providers: [cloud(), local()])
        )
        #expect(route.model == Self.onDevice)
        #expect(route.providerID == localID)
        #expect(route.change == .offlineFallback(previousProvider: "Test Cloud"))
    }

    @Test("with nothing on device, being offline surfaces the connection error")
    func offlineWithoutLocalStaysOnCloud() async {
        let router = makeRouter(reachability: FakeNetworkReachability(isReachable: false))
        let route = await router.resolve(request(model: Self.best, providers: [cloud()]))
        #expect(route.providerID == cloudID)
        #expect(route.change == nil)
    }

    @Test("an undownloaded on-device model is not a fallback")
    func offlineRequiresADownloadedModel() async {
        let router = makeRouter(
            reachability: FakeNetworkReachability(isReachable: false),
            localReady: false
        )
        let route = await router.resolve(
            request(model: Self.best, providers: [cloud(), local()])
        )
        #expect(route.providerID == cloudID)
    }

    @Test("coming back online returns to the user's provider and model untouched")
    func returnsToCloudWhenBackOnline() async {
        let reachability = FakeNetworkReachability(isReachable: false)
        let router = makeRouter(reachability: reachability)
        let providers = [cloud(), local()]

        let offline = await router.resolve(request(model: Self.second, providers: providers))
        #expect(offline.providerID == localID)
        // The caller only persists routes that stay on the user's provider, so the agent
        // still points at the cloud model on the next turn.
        #expect(offline.staysOn(providerID: cloudID) == false)

        reachability.isReachable = true
        let online = await router.resolve(request(model: Self.second, providers: providers))
        #expect(online.providerID == cloudID)
        #expect(online.model == Self.second)
        #expect(online.change == nil)
    }

    @Test("a connection coming back is trusted without waiting for a successful turn")
    func offlineSuspicionClearsWhenThePathReturns() async {
        let reachability = FakeNetworkReachability(isReachable: false)
        let router = makeRouter(reachability: reachability)
        // No on-device model yet, so the offline turn fails against the cloud provider.
        let cloudOnly = request(model: Self.best, providers: [cloud()])
        _ = await router.resolve(cloudOnly)
        await router.record(
            outcome(model: Self.best, timeToFirstToken: nil, result: .failed(.offline))
        )

        // The network returns, and an on-device model is now available. Nothing has
        // succeeded yet, so only the path itself can clear the suspicion.
        reachability.isReachable = true
        let route = await router.resolve(
            request(model: Self.best, providers: [cloud(), local()])
        )
        #expect(route.providerID == cloudID)
        #expect(route.change == nil)
    }

    @Test("a retry stays on the provider even while offline")
    func retryNeverChangesProvider() async {
        let router = makeRouter(reachability: FakeNetworkReachability(isReachable: false))
        let next = await router.retry(
            after: failure(503),
            request: request(model: Self.best, providers: [cloud(), local()])
        )
        #expect(next?.providerID == cloudID)
    }

    @Test("a user who chose the on-device provider is left alone")
    func deliberateLocalProviderIsNotRerouted() async {
        let router = makeRouter(reachability: FakeNetworkReachability(isReachable: false))
        let onLocal = RouteRequest(
            currentProviderID: localID,
            currentModel: Self.onDevice,
            isAuto: true,
            requirements: RouteRequirements(),
            providers: [cloud(), local()]
        )
        let route = await router.resolve(onLocal)
        #expect(route.providerID == localID)
        #expect(route.change == nil)
    }

    // MARK: - Slowness

    @Test("a persistently slow model is demoted on the next turn, not mid-turn")
    func slownessDemotesOnTheFollowingTurn() async {
        let router = makeRouter()
        let onBest = request(model: Self.best)

        for _ in 0 ..< 3 {
            await router.record(
                outcome(
                    model: Self.best,
                    timeToFirstToken: .seconds(25),
                    tokensPerSecond: 40,
                    result: .succeeded
                )
            )
            // Nothing is retried: the stream worked, it was just slow.
            #expect(await router.retry(after: failure(503), request: onBest) != nil)
        }

        #expect(await router.resolve(onBest).model != Self.best)
    }

    @Test("one slow turn is noise, not a demotion")
    func singleSlowTurnIsTolerated() async {
        let router = makeRouter()
        await router.record(
            outcome(
                model: Self.best,
                timeToFirstToken: .seconds(25),
                tokensPerSecond: 40,
                result: .succeeded
            )
        )
        #expect(await router.resolve(request(model: Self.best)).model == Self.best)
    }

    @Test("a cancelled turn says nothing about the model")
    func cancellationIsIgnored() async {
        let router = makeRouter()
        for _ in 0 ..< 5 {
            await router.record(
                outcome(model: Self.best, timeToFirstToken: .seconds(90), result: .cancelled)
            )
        }
        #expect(await router.resolve(request(model: Self.best)).model == Self.best)
    }

    // MARK: - Helpers

    private func outcome(
        model: String,
        timeToFirstToken: Duration? = .seconds(1),
        tokensPerSecond: Double? = 50,
        result: AttemptOutcome.Result
    ) -> AttemptOutcome {
        AttemptOutcome(
            providerID: cloudID,
            model: model,
            timeToFirstToken: timeToFirstToken,
            tokensPerSecond: tokensPerSecond,
            duration: .seconds(5),
            result: result
        )
    }
}
