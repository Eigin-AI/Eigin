@testable import Eigin
import Foundation
import Testing

@Suite("Relay status cache")
struct RelayModelStatusCacheTests {
    private actor Counter {
        var count = 0
        func increment() {
            count += 1
        }
    }

    private func request(auto: Bool = true, relay: Bool = true) -> RouteRequest {
        let id = UUID()
        return RouteRequest(
            currentProviderID: id,
            currentModel: "model",
            isAuto: auto,
            requirements: RouteRequirements(),
            providers: [
                RoutingProvider(
                    id: id,
                    name: "Test",
                    baseURL: relay ? "eigin-relay://" : "https://example.test",
                    availableModels: ["model"]
                ),
            ]
        )
    }

    @Test("Concurrent cold turns share one fetch and subsequent chats reuse it")
    func coalescesAndReuses() async {
        let client = FakeRelayClient()
        let count = Counter()
        client.modelStatusHandler = {
            await count.increment()
            try await Task.sleep(for: .milliseconds(30))
            return try JSONDecoder().decode(
                RelayModelStatusResponse.self,
                from: Data(#"{"generated_at":"2026-11-16T00:00:00Z","models":[]}"#.utf8)
            )
        }
        let cache = DefaultRelayModelStatusCache(client: client)
        async let first: Void = cache.prepare(for: request())
        async let second: Void = cache.prepare(for: request())
        _ = await (first, second)
        #expect(await cache.snapshot() != nil)
        await cache.prepare(for: request())
        #expect(await count.count == 1)
    }

    @Test("Pinned and BYO requests do not fetch shared health")
    func excludesUnrelatedRequests() async {
        let client = FakeRelayClient()
        let count = Counter()
        client.modelStatusHandler = {
            await count.increment()
            throw RelayClientError.notConfigured
        }
        let cache = DefaultRelayModelStatusCache(client: client)
        await cache.prepare(for: request(auto: false))
        await cache.prepare(for: request(relay: false))
        #expect(await count.count == 0)
    }

    @Test("Cold preflight stops waiting before a slow status fetch completes")
    func coldWaitIsBounded() async {
        let client = FakeRelayClient()
        client.modelStatusHandler = {
            try await Task.sleep(for: .seconds(2))
            throw RelayClientError.notConfigured
        }
        let cache = DefaultRelayModelStatusCache(client: client)
        let start = ContinuousClock.now
        await cache.prepare(for: request())
        #expect(start.duration(to: .now) < .seconds(1))
        #expect(await cache.snapshot() == nil)
    }

    @Test("Status timeouts leave Auto routing available without remote observations")
    func statusTimeoutDoesNotBlockRouting() async {
        let client = FakeRelayClient()
        let count = Counter()
        client.modelStatusHandler = {
            await count.increment()
            throw URLError(.timedOut)
        }
        let cache = DefaultRelayModelStatusCache(client: client)
        let request = request()
        await cache.prepare(for: request)
        #expect(await cache.snapshot() == nil)
        let router = DefaultModelRouter(
            reachability: FakeNetworkReachability(),
            localModelReadiness: { false },
            remoteHealthSource: cache
        )
        let route = await router.resolve(request)
        #expect(route.model == request.currentModel)
        #expect(route.providerID == request.currentProviderID)
        await cache.prepare(for: request)
        #expect(await count.count == 1)
    }
}
