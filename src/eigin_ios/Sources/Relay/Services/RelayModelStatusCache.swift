import Foundation

/// Cached advisory health; network work stays outside the router.
protocol RelayModelStatusSource: RemoteModelHealthSource {
    func snapshot() async -> RelayModelStatusSnapshot?
    func refreshIfNeeded() async
    func prepare(for request: RouteRequest) async
}

/// Coalesces relay status fetches and bounds cold-cache preflight waiting.
actor DefaultRelayModelStatusCache: RelayModelStatusSource {
    private let client: any RelayClient
    private let refreshInterval: TimeInterval
    private let now: @Sendable () -> Date
    private var cached: RelayModelStatusSnapshot?
    private var lastAttempt: Date?
    private var refresh: Task<Void, Never>?

    init(
        client: any RelayClient,
        refreshInterval: TimeInterval = 300,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.client = client
        self.refreshInterval = refreshInterval
        self.now = now
    }

    func health(for provider: RoutingProvider) -> [String: RemoteModelHealth] {
        cached?.health(for: provider) ?? [:]
    }

    func snapshot() -> RelayModelStatusSnapshot? {
        cached
    }

    func refreshIfNeeded() {
        guard refresh == nil,
              lastAttempt.map({ now().timeIntervalSince($0) >= refreshInterval }) ?? true
        else { return }
        lastAttempt = now()
        refresh = Task { [weak self, client] in
            let response = try? await client.modelStatus()
            await self?.complete(response)
        }
    }

    private func complete(_ response: RelayModelStatusResponse?) {
        if let response { cached = RelayModelStatusSnapshot(response: response, receivedAt: now()) }
        refresh = nil
    }

    func prepare(for request: RouteRequest) async {
        guard request.isAuto, let provider = request.currentProvider,
              ProviderPreset.isRelay(provider.baseURL)
        else { return }
        refreshIfNeeded()
        guard cached == nil, refresh != nil else { return }
        // Polling the cache avoids structured-task cancellation waiting for a slow
        // transport to finish. The independently bounded fetch can fill it later.
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(500))
        while cached == nil, refresh != nil, ContinuousClock.now < deadline {
            do { try await Task.sleep(for: .milliseconds(10)) }
            catch { return }
        }
    }
}
