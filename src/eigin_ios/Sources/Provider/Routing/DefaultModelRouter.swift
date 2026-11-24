import EiginSDK
import Foundation

/// Shared SDK routing policy with host-owned reachability observation.
actor DefaultModelRouter: ModelRouter {
    static let firstTokenCeiling: Duration = .seconds(20)
    static let hedgeDelay: Duration = .seconds(6)

    let policy = EiginSDK.Experimental.Routing.Router.withCatalog()
    let remoteHealthSource: (any RemoteModelHealthSource)?
    let reachability: any NetworkReachability
    let localModelReadiness: @Sendable () -> Bool
    let now: @Sendable () -> Date

    init(
        reachability: any NetworkReachability,
        localModelReadiness: @escaping @Sendable () -> Bool,
        now: @escaping @Sendable () -> Date = { Date() },
        remoteHealthSource: (any RemoteModelHealthSource)? = nil
    ) {
        self.reachability = reachability
        self.localModelReadiness = localModelReadiness
        self.now = now
        self.remoteHealthSource = remoteHealthSource
    }

    func resolve(_ request: RouteRequest) async -> ResolvedRoute {
        let timestamp = now()
        policy.recordReachability(reachable: reachability.isReachable)
        if request.isAuto, let provider = request.currentProvider {
            await refreshHealth(provider)
            if let offline = offlineRoute(for: request, at: timestamp) { return offline }
        }
        let route = policy.resolve(
            request: RoutingSDKConversion.request(request), now: timestamp.timeIntervalSince1970,
            decisionTime: now().timeIntervalSince1970
        )
        return mapped(route, request: request)
    }

    func retry(after error: Error, request: RouteRequest) async -> ResolvedRoute? {
        let timestamp = now()
        let input = RoutingSDKConversion.request(request)
        let demand = policy.replacementDemand(request: input)
        guard request.isAuto, let provider = request.currentProvider else { return nil }
        await refreshHealth(provider)
        return policy.replacement(
            request: input,
            failure: RoutingSDKConversion.failure(RoutingFailure(from: error)),
            reasoningDemand: demand,
            now: timestamp.timeIntervalSince1970,
            decisionTime: now().timeIntervalSince1970
        ).map { mapped($0, request: request) }
    }

    func canSatisfy(_ request: RouteRequest) async -> Bool {
        guard let provider = request.currentProvider else { return false }
        if request.isAuto { await refreshHealth(provider) }
        return policy.canSatisfy(
            request: RoutingSDKConversion.request(request), now: now().timeIntervalSince1970
        )
    }

    func reasoningEffort(for model: String, request: RouteRequest) async -> ReasoningEffort? {
        policy.reasoningEffort(request: RoutingSDKConversion.request(request), model: model)
            .map(ReasoningEffort.init)
    }

    func hedgeDelay(for model: String) async -> Duration {
        .seconds(policy.hedgeDelay(model: model))
    }

    func hedgeCandidate(after model: String, request: RouteRequest) async -> ResolvedRoute? {
        policy.hedgeCandidate(
            request: RoutingSDKConversion.request(request), model: model,
            now: now().timeIntervalSince1970
        ).map { RoutingSDKConversion.route($0, request: request) }
    }

    func recordHedgeLoss(_ model: String, silentFor: Duration) async {
        AppLogger.info(
            "Hedge loser \(public: model), silent for \(public: String(describing: silentFor))",
            category: .routing
        )
        policy.recordHedgeLoss(model: model, now: now().timeIntervalSince1970)
    }

    func record(_ attempt: AttemptOutcome) async {
        if case .cancelled = attempt.result { return }
        AppLogger.debug(
            "Attempt \(public: attempt.model): \(public: String(describing: attempt.result)), ttft \(public: String(describing: attempt.timeToFirstToken)), throughput \(public: String(describing: attempt.tokensPerSecond)), duration \(public: String(describing: attempt.duration))",
            category: .routing
        )
        policy.record(
            outcome: RoutingSDKConversion.outcome(attempt),
            now: now().timeIntervalSince1970
        )
    }

    private func refreshHealth(_ provider: RoutingProvider) async {
        let observations = await remoteHealthSource?.health(for: provider) ?? [:]
        policy.replaceRemoteHealth(
            providerId: provider.id.uuidString,
            observations: RoutingSDKConversion.remote(observations)
        )
    }

    private func mapped(
        _ decision: EiginSDK.Experimental.Routing.Decision, request: RouteRequest
    ) -> ResolvedRoute {
        let route = RoutingSDKConversion.route(decision, request: request)
        if let change = route.change {
            AppLogger.info(
                "Routing to \(public: route.model): \(public: String(describing: change))",
                category: .routing
            )
        }
        return route
    }
}
