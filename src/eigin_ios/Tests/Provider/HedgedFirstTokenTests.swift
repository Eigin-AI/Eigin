@testable import Eigin
import Foundation
import os
import Testing

@Suite("Hedged first-token race")
struct HedgedFirstTokenTests {
    // MARK: - Fixtures

    private func makeStream()
        -> (
            stream: AsyncThrowingStream<Int, Error>,
            continuation: AsyncThrowingStream<Int, Error>.Continuation
        )
    {
        var continuation: AsyncThrowingStream<Int, Error>.Continuation!
        let stream = AsyncThrowingStream { continuation = $0 }
        return (stream, continuation)
    }

    /// Thread-safe event logger for background consumers.
    private final class Collector: @unchecked Sendable {
        private let lock = OSAllocatedUnfairLock(initialState: [Int]())
        var items: [Int] {
            lock.withLock { $0 }
        }

        func append(_ value: Int) {
            lock.withLock { $0.append(value) }
        }
    }

    /// Tracks how the race's lazily-opened sides behaved.
    private final class DispatchLog: @unchecked Sendable {
        let primaryModels = OSAllocatedUnfairLock(initialState: [String]())
        let fallbackOpened = OSAllocatedUnfairLock(initialState: false)
        let failures = OSAllocatedUnfairLock(initialState: [(String, any Error)]())
        let replacements = OSAllocatedUnfairLock(initialState: [String]())
        let losers = OSAllocatedUnfairLock(initialState: [(String, Duration)]())

        func recordPrimary(_ model: String) {
            primaryModels.withLock { $0.append(model) }
        }
    }

    // MARK: - Race behaviour

    @Test("Primary speaks first: runner-up never opens, nobody loses")
    func primaryWinsBeforeDelay() async throws {
        let (primary, primaryTx) = makeStream()
        let (fallback, fallbackTx) = makeStream()
        let opened = DispatchLog()
        let attribution = RaceWinner()

        let raced = withHedgedFirstToken(
            primaryModel: "glm-5.3",
            plan: HedgePlan(delay: .milliseconds(200), fallbackModel: "glm-5.2"),
            ceiling: .seconds(2),
            raceWinner: attribution,
            openPrimary: { model in
                opened.recordPrimary(model)
                return primary
            },
            openFallback: {
                opened.fallbackOpened.withLock { $0 = true }
                return fallback
            },
            primaryFailed: { model, error in
                opened.failures.withLock { $0.append((model, error)) }
                return nil
            },
            onLoser: { model, silentFor in
                opened.losers.withLock { $0.append((model, silentFor)) }
            }
        )

        let received = Collector()
        let consumer = Task {
            for try await event in raced {
                received.append(event)
            }
        }

        primaryTx.yield(1)
        try await Task.sleep(for: .milliseconds(400))
        primaryTx.finish()
        try await Task.sleep(for: .milliseconds(50))
        consumer.cancel()

        #expect(received.items == [1])
        #expect(!opened.fallbackOpened.withLock { $0 })
        #expect(opened.losers.withLock { $0.isEmpty })
        #expect(attribution.current == "glm-5.3")
        #expect(opened.primaryModels.withLock { $0 == ["glm-5.3"] })
    }

    @Test("Runner-up wins the race: attributed to the turn, primary reported as lost")
    func fallbackWins() async throws {
        let (primary, primaryTx) = makeStream()
        let (fallback, fallbackTx) = makeStream()
        let opened = DispatchLog()
        let attribution = RaceWinner()

        let raced = withHedgedFirstToken(
            primaryModel: "glm-5.3",
            plan: HedgePlan(delay: .milliseconds(50), fallbackModel: "glm-5.2"),
            ceiling: .seconds(2),
            raceWinner: attribution,
            openPrimary: { model in
                opened.recordPrimary(model)
                return primary
            },
            openFallback: {
                opened.fallbackOpened.withLock { $0 = true }
                return fallback
            },
            primaryFailed: { model, error in
                opened.failures.withLock { $0.append((model, error)) }
                return nil
            },
            onLoser: { model, silentFor in
                opened.losers.withLock { $0.append((model, silentFor)) }
            }
        )

        let received = Collector()
        let consumer = Task {
            for try await event in raced {
                received.append(event)
            }
        }

        try await Task.sleep(for: .milliseconds(150))
        #expect(opened.fallbackOpened.withLock { $0 })

        fallbackTx.yield(20)
        try await Task.sleep(for: .milliseconds(100))
        primaryTx.yield(10) // late: the race is already decided
        fallbackTx.yield(21)
        try await Task.sleep(for: .milliseconds(50))
        fallbackTx.finish()
        try await Task.sleep(for: .milliseconds(50))
        consumer.cancel()

        #expect(received.items == [20, 21])
        #expect(attribution.current == "glm-5.2")

        let recorded = opened.losers.withLock { $0 }
        #expect(recorded.count == 1)
        #expect(recorded.first?.0 == "glm-5.3")
        #expect((recorded.first?.1 ?? .zero) >= .milliseconds(50))
    }

    @Test("Nothing speaks before the ceiling: the whole race fails to retry")
    func ceilingFiresWhenBothSilent() async throws {
        let (primary, primaryTx) = makeStream()
        let (fallback, fallbackTx) = makeStream()
        let opened = DispatchLog()
        let attribution = RaceWinner()

        let raced = withHedgedFirstToken(
            primaryModel: "glm-5.3",
            plan: HedgePlan(delay: .milliseconds(20), fallbackModel: "glm-5.2"),
            ceiling: .milliseconds(120),
            raceWinner: attribution,
            openPrimary: { model in
                opened.recordPrimary(model)
                return primary
            },
            openFallback: {
                opened.fallbackOpened.withLock { $0 = true }
                return fallback
            },
            primaryFailed: { model, error in
                opened.failures.withLock { $0.append((model, error)) }
                return nil
            },
            onLoser: { _, _ in }
        )

        var caught: (any Error)?
        do {
            for try await _ in raced {}
        } catch {
            caught = error
        }

        #expect(caught is FirstEventTimeout)
        #expect(opened.fallbackOpened.withLock { $0 })
        #expect(attribution.current == nil)

        primaryTx.finish()
        fallbackTx.finish()
    }

    @Test("A slow handshake is hedged: fallback wins before the primary opens")
    func handshakeStallIsHedged() async throws {
        let (primary, primaryTx) = makeStream()
        let (fallback, fallbackTx) = makeStream()
        let opened = DispatchLog()
        let attribution = RaceWinner()

        let raced = withHedgedFirstToken(
            primaryModel: "glm-5.3",
            plan: HedgePlan(delay: .milliseconds(60), fallbackModel: "glm-5.2"),
            ceiling: .seconds(2),
            raceWinner: attribution,
            openPrimary: { model in
                opened.recordPrimary(model)
                // The hang: headers take 300ms and no token ever follows.
                try? await Task.sleep(for: .milliseconds(300))
                return primary
            },
            openFallback: {
                opened.fallbackOpened.withLock { $0 = true }
                return fallback
            },
            primaryFailed: { model, error in
                opened.failures.withLock { $0.append((model, error)) }
                return nil
            },
            onLoser: { model, silentFor in
                opened.losers.withLock { $0.append((model, silentFor)) }
            }
        )

        let received = Collector()
        let consumer = Task {
            for try await event in raced {
                received.append(event)
            }
        }

        try await Task.sleep(for: .milliseconds(150))
        #expect(opened.fallbackOpened.withLock { $0 })
        fallbackTx.yield(20)
        try await Task.sleep(for: .milliseconds(150))
        fallbackTx.finish()
        try await Task.sleep(for: .milliseconds(50))
        consumer.cancel()

        #expect(received.items == [20])
        #expect(attribution.current == "glm-5.2")
        let recorded = opened.losers.withLock { $0 }
        #expect(recorded.count == 1)
        #expect(recorded.first?.0 == "glm-5.3")
    }

    @Test("A failed runner-up dispatch degrades silently to primary only")
    func failedDispatchDegradesToPrimary() async throws {
        let (primary, primaryTx) = makeStream()
        let opened = DispatchLog()
        let attribution = RaceWinner()

        let raced = withHedgedFirstToken(
            primaryModel: "glm-5.3",
            plan: HedgePlan(delay: .milliseconds(20), fallbackModel: "glm-5.2"),
            ceiling: .seconds(2),
            raceWinner: attribution,
            openPrimary: { model in
                opened.recordPrimary(model)
                return primary
            },
            openFallback: { nil },
            primaryFailed: { model, error in
                opened.failures.withLock { $0.append((model, error)) }
                return nil
            },
            onLoser: { model, silentFor in
                opened.losers.withLock { $0.append((model, silentFor)) }
            }
        )

        let received = Collector()
        let consumer = Task {
            for try await event in raced {
                received.append(event)
            }
        }

        try await Task.sleep(for: .milliseconds(100))
        primaryTx.yield(1)
        try await Task.sleep(for: .milliseconds(50))
        primaryTx.finish()
        try await Task.sleep(for: .milliseconds(50))
        consumer.cancel()

        #expect(attribution.current == "glm-5.3")
        #expect(opened.losers.withLock { $0.isEmpty })
    }

    @Test("Primary dispatch failure re-dispatches under a new model and continues")
    func primaryFailureRedispatches() async throws {
        let opened = DispatchLog()
        let replacement = makeStream()
        let attribution = RaceWinner()

        let raced = withHedgedFirstToken(
            primaryModel: "glm-5.3",
            plan: nil,
            ceiling: .seconds(2),
            raceWinner: attribution,
            openPrimary: { model in
                opened.recordPrimary(model)
                if model == "glm-5.3" {
                    throw DispatchFailure()
                }
                return replacement.stream
            },
            openFallback: { nil },
            primaryFailed: { model, error in
                opened.failures.withLock { $0.append((model, error)) }
                opened.replacements.withLock { $0.append("gpt-5.6") }
                return ("gpt-5.6", replacement.stream)
            },
            onLoser: { model, silentFor in
                opened.losers.withLock { $0.append((model, silentFor)) }
            }
        )

        let received = Collector()
        let consumer = Task {
            for try await event in raced {
                received.append(event)
            }
        }

        try await Task.sleep(for: .milliseconds(50))
        replacement.continuation.yield(7)
        try await Task.sleep(for: .milliseconds(50))
        replacement.continuation.finish()
        try await Task.sleep(for: .milliseconds(50))
        consumer.cancel()

        #expect(received.items == [7])
        #expect(attribution.current == "gpt-5.6")
        #expect(opened.failures.withLock { $0.count } == 1)
        #expect(opened.replacements.withLock { $0 == ["gpt-5.6"] })
    }

    @Test("Primary fails after the runner-up opened: the runner-up keeps the race")
    func primaryFailureWithRunnerUpAttached() async throws {
        let (primary, primaryTx) = makeStream()
        let (fallback, fallbackTx) = makeStream()
        let opened = DispatchLog()
        let attribution = RaceWinner()

        let raced = withHedgedFirstToken(
            primaryModel: "glm-5.3",
            plan: HedgePlan(delay: .milliseconds(20), fallbackModel: "glm-5.2"),
            ceiling: .seconds(2),
            raceWinner: attribution,
            openPrimary: { model in
                opened.recordPrimary(model)
                return primary
            },
            openFallback: {
                opened.fallbackOpened.withLock { $0 = true }
                return fallback
            },
            primaryFailed: { model, error in
                opened.failures.withLock { $0.append((model, error)) }
                return nil
            },
            onLoser: { _, _ in }
        )

        let received = Collector()
        let consumer = Task {
            for try await event in raced {
                received.append(event)
            }
        }

        try await Task.sleep(for: .milliseconds(80))
        #expect(opened.fallbackOpened.withLock { $0 })
        // The primary dies while the runner-up is live and neither has spoken.
        primaryTx.finish(throwing: DispatchFailure())
        try await Task.sleep(for: .milliseconds(60))

        // The race must survive; the runner-up still carries the turn.
        fallbackTx.yield(20)
        try await Task.sleep(for: .milliseconds(60))
        #expect(received.items == [20])
        #expect(attribution.current == "glm-5.2")

        fallbackTx.finish()
        try await Task.sleep(for: .milliseconds(30))
        consumer.cancel()
        #expect(opened.losers.withLock { $0.isEmpty })
    }

    @Test("Terminal primary failure surfaces the error to the consumer")
    func terminalFailureSurfaces() async throws {
        let opened = DispatchLog()
        let attribution = RaceWinner()

        let raced = withHedgedFirstToken(
            primaryModel: "glm-5.3",
            plan: nil,
            ceiling: .seconds(2),
            raceWinner: attribution,
            openPrimary: { (_: String) -> AsyncThrowingStream<Int, Error> in
                throw DispatchFailure()
            },
            openFallback: { nil },
            primaryFailed: { model, error in
                opened.failures.withLock { $0.append((model, error)) }
                return nil
            },
            onLoser: { _, _ in }
        )

        var caught: (any Error)?
        do {
            for try await _ in raced {}
        } catch {
            caught = error
        }

        #expect(caught is DispatchFailure)
        #expect(opened.failures.withLock { $0.count } == 1)
    }

    private struct DispatchFailure: Error {}
}

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

        #expect(await router.hedgeDelay(for: Self.best) == DefaultModelRouter.slowModelHedgeDelay)
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
        clock.advance(ModelHealthStore.slownessQuarantine.seconds + 1)
        #expect(
            await router.hedgeCandidate(after: Self.best, request: request(model: Self.best))?
                .model == Self.second
        )
    }
}
