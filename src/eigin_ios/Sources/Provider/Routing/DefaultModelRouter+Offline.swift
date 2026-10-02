import Foundation

// MARK: - Offline fallback

extension DefaultModelRouter {
    /// The on-device model, when there is no usable network and a ready one to fall to.
    ///
    /// Two signals, because a satisfied path does not prove the internet is reachable:
    /// the path monitor, and a request that already failed as offline.
    func offlineRoute(for request: RouteRequest, at timestamp: Date) -> ResolvedRoute? {
        guard !reachability.isReachable || sawOfflineFailure else { return nil }
        guard let current = request.currentProvider, !current.isLocal else { return nil }

        let signal = reachability.isReachable ? "a failed request" : "the path monitor"
        func declined(_ why: String) -> ResolvedRoute? {
            AppLogger.info(
                "Offline per \(public: signal) but \(public: why); staying on \(public: current.name)",
                category: .routing
            )
            return nil
        }

        guard let local = request.providers.first(where: \.isLocal) else {
            return declined("no on-device model is set up")
        }
        guard localModelReadiness() else {
            return declined("the on-device model is not downloaded")
        }
        // Rank-best, not array-first: with two on-device models enabled the fallback
        // should pick the stronger one, matching rankedCandidates' best-first intent.
        guard let model = offer(for: local).min(by: { rank(of: $0) < rank(of: $1) }) else {
            return declined("the on-device provider lists no model")
        }

        health.markActivity(now: timestamp)
        AppLogger.info(
            "Offline per \(public: signal); routing to on-device \(public: model). \(public: current.name) stays the agent's provider",
            category: .routing
        )
        return ResolvedRoute(
            providerID: local.id,
            baseURL: local.baseURL,
            model: model,
            change: .offlineFallback(previousProvider: current.name)
        )
    }

    /// Clears the offline suspicion when the path itself comes back, so a connection that
    /// returns is trusted without waiting for a successful turn to prove it.
    func noteReachability() {
        let reachable = reachability.isReachable
        defer { wasReachable = reachable }
        guard reachable, !wasReachable else { return }
        sawOfflineFailure = false
    }
}
