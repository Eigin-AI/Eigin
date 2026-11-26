@testable import Eigin
import Foundation
import os
import Testing

@Suite("DefaultModelRouter hedging")
struct RouterHedgeTests {
    // MARK: - Fixtures

    /// Ranked best-first in ``KnownModelCatalog``. All support tools.
    static let best = "claude-sonnet-5"
    static let second = "gpt-5.6"
    static let third = "gemini-3.5-flash"

    private let providerID = UUID()

    private final class TestClock: @unchecked Sendable {
        private let state = OSAllocatedUnfairLock(initialState: Date(timeIntervalSince1970: 0))
        var now: Date {
            state.withLock { $0 }
        }

        func advance(_ interval: TimeInterval) {
            state.withLock { $0 = $0.addingTimeInterval(interval) }
        }
    }

    private func makeRouter(clock: TestClock) -> DefaultModelRouter {
        DefaultModelRouter(
            reachability: FakeNetworkReachability(),
            localModelReadiness: { true },
            now: { clock.now }
        )
    }

    private func request(model: String) -> RouteRequest {
        RouteRequest(
            currentProviderID: providerID,
            currentModel: model,
            isAuto: true,
            requirements: RouteRequirements(),
            providers: [
                RoutingProvider(
                    id: providerID,
                    name: "Cloud",
                    baseURL: "https://cloud.test/v1",
                    availableModels: [Self.best, Self.second, Self.third]
                ),
            ]
        )
    }

    // MARK: - Adaptive delay

    @Test("A healthy model gets the default hedge delay")
    func healthyModelGetsDefaultDelay() async {
        let router = makeRouter(clock: TestClock())
        let delay = await router.hedgeDelay(for: Self.best)
        #expect(delay == DefaultModelRouter.hedgeDelay)
    }

    @Test("Recent slow first tokens shorten the delay, two is the trigger")
    func slowModelGetsShortenedDelay() async {
        let clock = TestClock()
        let router = makeRouter(clock: clock)

        #expect(await router.hedgeDelay(for: Self.best) == DefaultModelRouter.hedgeDelay)

        // Two slow turns: the pattern that earns less patience, but below the
        // three slow samples that demote the model outright.
        for _ in 0 ..< 2 {
            await router.record(
                AttemptOutcome(
                    providerID: providerID,
                    model: Self.best,
                    timeToFirstToken: .seconds(12),
                    tokensPerSecond: nil,
                    duration: .seconds(12),
                    result: .succeeded
                )
            )
            clock.advance(1)
        }

        #expect(await router.hedgeDelay(for: Self.best) == .seconds(3))
    }

    // MARK: - Runner-up selection

    @Test("The hedge candidate is the next ranked model on the same provider")
    func hedgeCandidatePicksTheRunnerUp() async {
        let router = makeRouter(clock: TestClock())
        let route = await router.hedgeCandidate(
            after: Self.best,
            request: request(model: Self.best)
        )
        #expect(route?.model == Self.second)
        #expect(route?.providerID == providerID)
    }

    @Test("A quarantined model is never picked as the runner-up")
    func hedgeCandidateSkipsQuarantined() async {
        let clock = TestClock()
        let router = makeRouter(clock: clock)

        // Quarantine the runner-up with repeated overload failures.
        for _ in 0 ..< 3 {
            await router.record(
                AttemptOutcome(
                    providerID: providerID,
                    model: Self.second,
                    timeToFirstToken: nil,
                    tokensPerSecond: nil,
                    duration: .seconds(1),
                    result: .failed(.providerOverloaded)
                )
            )
            clock.advance(1)
        }

        let route = await router.hedgeCandidate(
            after: Self.best,
            request: request(model: Self.best)
        )
        #expect(route?.model == Self.third)
    }

    // MARK: - Hedge losses

    @Test("One hedge loss is noise; a pattern of them demotes the model")
    func hedgeLossQuarantinesOnSecondLoss() async {
        let clock = TestClock()
        let router = makeRouter(clock: clock)

        await router.recordHedgeLoss(Self.second, silentFor: .seconds(6))
        clock.advance(1)
        await router.recordHedgeLoss(Self.second, silentFor: .seconds(6))
        clock.advance(1)

        // Second loss: benched; the top-ranked model's runner-up is now third.
        #expect(
            await router.hedgeCandidate(after: Self.best, request: request(model: Self.best))?
                .model == Self.third
        )

        // Slowness quarantine is 2 minutes; past it the model is a candidate
        // again - one prove-it turn decides its next bench.
        clock.advance(121)
        #expect(
            await router.hedgeCandidate(after: Self.best, request: request(model: Self.best))?
                .model == Self.second
        )
    }
}
