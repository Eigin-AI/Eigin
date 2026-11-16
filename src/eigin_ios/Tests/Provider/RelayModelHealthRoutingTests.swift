@testable import Eigin
import Foundation
import os
import Testing

@Suite("Relay model health routing")
struct RelayModelHealthRoutingTests {
    private actor Status: RelayModelStatusSource {
        var value: RelayModelStatusSnapshot?
        func set(_ value: RelayModelStatusSnapshot?) {
            self.value = value
        }

        func health(for provider: RoutingProvider) async -> [String: RemoteModelHealth] {
            value?.health(for: provider) ?? [:]
        }

        func snapshot() async -> RelayModelStatusSnapshot? {
            value
        }

        func refreshIfNeeded() async {}
        func prepare(for _: RouteRequest) async {}
    }

    private final class Clock: @unchecked Sendable {
        let state = OSAllocatedUnfairLock(initialState: Date(timeIntervalSince1970: 1_800_000_000))
        var now: Date {
            state.withLock { $0 }
        }

        func advance(_ seconds: TimeInterval) {
            state.withLock { $0 += seconds }
        }
    }

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let providerID = UUID()
    private let best = "claude-sonnet-5"
    private let models = ["claude-sonnet-5", "gpt-5.6", "gemini-3.5-flash"]

    private func request(
        auto: Bool = true,
        relay: Bool = true,
        conversation: UUID = UUID()
    ) -> RouteRequest {
        RouteRequest(
            currentProviderID: providerID,
            currentModel: best,
            isAuto: auto,
            requirements: RouteRequirements(),
            providers: [RoutingProvider(
                id: providerID, name: "Test",
                baseURL: relay ? "eigin-relay://" : "https://example.test/v1",
                availableModels: models
            )],
            conversationID: conversation
        )
    }

    private func summary(
        at: Double = -60,
        expires: Double = 800,
        ttft: Double? = nil,
        tps: Double? = nil,
        failure: Bool = false
    ) -> [String: Any] {
        let date = { (offset: Double) in
            ISO8601DateFormatter().string(from: now.addingTimeInterval(offset))
        }
        var result: [String: Any] = [
            "sampled_at": date(at), "expires_at": date(expires),
            "success_count": failure ? 0 : 4, "failure_count": failure ? 4 : 0,
            "ttft_sample_count": ttft == nil ? 0 : 4, "throughput_sample_count": tps == nil ? 0 : 4,
        ]
        if let ttft { result["ttft_p50_ms"] = ttft; result["ttft_sampled_at"] = date(at) }
        if let tps { result["tps_p50"] = tps; result["tps_sampled_at"] = date(at) }
        return result
    }

    private func snapshot(
        traffic: [String: Any]? = nil,
        probe: [String: Any]? = nil
    ) throws -> RelayModelStatusSnapshot {
        var model: [String: Any] = ["id": best]
        model["traffic"] = traffic
        model["probes"] = probe
        let data = try JSONSerialization.data(withJSONObject: [
            "generated_at": ISO8601DateFormatter().string(from: now), "models": [model],
        ])
        return try RelayModelStatusSnapshot(
            response: JSONDecoder().decode(RelayModelStatusResponse.self, from: data),
            receivedAt: now
        )
    }

    private func router(_ source: Status, clock: Clock = Clock()) -> DefaultModelRouter {
        DefaultModelRouter(
            reachability: FakeNetworkReachability(),
            localModelReadiness: { false },
            now: { clock.now },
            remoteHealthSource: source
        )
    }

    private func success(
        ttft: Duration? = nil,
        tps: Double? = nil
    ) -> AttemptOutcome {
        AttemptOutcome(
            providerID: providerID,
            model: best,
            timeToFirstToken: ttft,
            tokensPerSecond: tps,
            duration: .seconds(2),
            result: .succeeded
        )
    }

    @Test("Fresh shared slowness and failed probes avoid the preferred model")
    func firstTurn() async throws {
        for snapshot in try [
            snapshot(traffic: summary(ttft: 15000)),
            snapshot(probe: summary(failure: true)),
        ] {
            let source = Status()
            await source.set(snapshot)
            #expect(await router(source).resolve(request()).model != best)
        }
    }

    @Test("Expired evidence, pinned choices, and BYO preserve routing")
    func noApplicableEvidence() async throws {
        let source = Status()
        try await source.set(snapshot(traffic: summary(expires: -1, ttft: 15000)))
        #expect(await router(source).resolve(request()).model == best)
        try await source.set(snapshot(traffic: summary(ttft: 15000)))
        #expect(await router(source).resolve(request(auto: false)).model == best)
        #expect(await router(source).resolve(request(relay: false)).model == best)
    }

    @Test("Newer outcome-only traffic preserves applicable probe throughput")
    func selectsEvidencePerMetric() async throws {
        let source = Status()
        try await source.set(snapshot(traffic: summary(at: -10), probe: summary(at: -60, tps: 3)))
        #expect(await router(source).resolve(request()).model != best)
    }

    @Test("Newer outcome-only traffic cannot renew an old speed measurement")
    func metricRecencyAndLocalOverride() async throws {
        let source = Status()
        let clock = Clock()
        try await source.set(snapshot(traffic: summary(ttft: 15000)))
        let router = router(source, clock: clock)
        _ = await router.resolve(request())
        await router.record(success(ttft: .seconds(1)))
        await router.record(success())
        clock.advance(600)
        var traffic = summary(ttft: 15000)
        traffic["sampled_at"] = ISO8601DateFormatter().string(from: now.addingTimeInterval(500))
        try await source.set(snapshot(traffic: traffic))
        #expect(await router.resolve(request()).model == best)
    }

    @Test("Missing local measurements cannot clear shared speed degradation")
    func missingLocalSpeedDoesNotClearRemoteEvidence() async throws {
        for traffic in [summary(ttft: 15000), summary(tps: 3)] {
            let source = Status()
            try await source.set(snapshot(traffic: traffic))
            let router = router(source)
            _ = await router.resolve(request())
            await router.record(success())
            #expect(await router.resolve(request()).model != best)
        }
    }

    @Test("One slow local attempt uses the same demotion policy with or without shared health")
    func preservesLocalSamplePolicy() async throws {
        for shared in [false, true] {
            let source = Status()
            if shared { try await source.set(snapshot(traffic: summary(ttft: 1000, tps: 20))) }
            let router = router(source)
            _ = await router.resolve(request())
            await router.record(success(ttft: .seconds(15), tps: 3))
            #expect(await router.resolve(request()).model == best)
        }
    }

    @Test(
        "Slow anchors switch, each degraded metric must recover, and healthy replacements stay sticky"
    )
    func switchingAndRecovery() async throws {
        let source = Status()
        let clock = Clock()
        let router = router(source, clock: clock)
        let conversation = request()
        #expect(await router.resolve(conversation).model == best)
        try await source.set(snapshot(traffic: summary(ttft: 15000, tps: 3)))
        let replacement = await router.resolve(conversation).model
        #expect(replacement != best)
        clock.advance(10)
        try await source.set(snapshot(traffic: summary(at: 5, ttft: 7000, tps: 5.5)))
        #expect(await router.resolve(request()).model != best)
        clock.advance(10)
        try await source.set(snapshot(traffic: summary(at: 15, ttft: 7000, tps: 7)))
        #expect(await router.resolve(request()).model == best)
        #expect(await router.resolve(conversation).model == replacement)
    }

    @Test("Newer probe failure overrides older traffic and newer traffic restores eligibility")
    func outcomePrecedence() async throws {
        let source = Status()
        let clock = Clock()
        let router = router(source, clock: clock)
        try await source.set(snapshot(
            traffic: summary(at: -60),
            probe: summary(at: -10, failure: true)
        ))
        #expect(await router.resolve(request()).model != best)
        clock.advance(10)
        try await source.set(snapshot(
            traffic: summary(at: 5),
            probe: summary(at: -10, failure: true)
        ))
        #expect(await router.resolve(request()).model == best)
    }

    @Test("Missing measurements cannot keep expired degradation alive")
    func retainedMetricExpires() async throws {
        let source = Status()
        let clock = Clock()
        let router = router(source, clock: clock)
        try await source.set(snapshot(traffic: summary(expires: 20, tps: 3)))
        #expect(await router.resolve(request()).model != best)
        clock.advance(30)
        try await source.set(snapshot(traffic: summary(at: 25)))
        #expect(await router.resolve(request()).model == best)
    }

    @Test("Older traffic cannot recover a newer slow probe when its replacement has no TPS")
    func recoveryRequiresNewerMeasurement() async throws {
        let source = Status()
        let clock = Clock()
        let router = router(source, clock: clock)
        let oldTraffic = summary(at: -120, tps: 20)
        try await source.set(snapshot(traffic: oldTraffic, probe: summary(at: -60, tps: 3)))
        #expect(await router.resolve(request()).model != best)
        try await source.set(snapshot(traffic: oldTraffic, probe: summary(at: -10)))
        #expect(await router.resolve(request()).model != best)
        clock.advance(10)
        try await source.set(snapshot(traffic: summary(at: 5, tps: 20), probe: summary(at: -10)))
        #expect(await router.resolve(request()).model == best)
    }

    @Test("Measured local throughput overrides older remote throughput")
    func localThroughputOverridesOlderRemoteEvidence() async throws {
        let source = Status()
        try await source.set(snapshot(traffic: summary(tps: 3)))
        let router = router(source)
        _ = await router.resolve(request())
        await router.record(success(ttft: .seconds(1), tps: 20))
        #expect(await router.resolve(request()).model == best)
    }

    @Test("Routing accepts provider-neutral remote observations")
    func providerNeutralRemoteSource() async {
        struct Source: RemoteModelHealthSource {
            let values: [String: RemoteModelHealth]
            func health(for _: RoutingProvider) async -> [String: RemoteModelHealth] {
                values
            }
        }
        let measured = RemoteHealthSample(
            value: 15000,
            count: 4,
            source: .requests,
            observedAt: now.addingTimeInterval(-10),
            expiresAt: now.addingTimeInterval(60)
        )
        let source = Source(values: [best: RemoteModelHealth(ttft: [measured])])
        let date = now
        let router = DefaultModelRouter(
            reachability: FakeNetworkReachability(),
            localModelReadiness: { false },
            now: { date },
            remoteHealthSource: source
        )
        #expect(await router.resolve(request(relay: false)).model != best)
    }
}
