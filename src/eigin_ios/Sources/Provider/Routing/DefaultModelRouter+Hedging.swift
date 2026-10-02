import Foundation

// MARK: - Hedging

extension DefaultModelRouter {
    /// How long a model may stay silent before the turn opens a runner-up alongside it.
    /// Healthy cloud TTFT is 1–5s, so most turns never hedge at all; this is a patience
    /// ceiling, not the common path.
    static let hedgeDelay: Duration = .seconds(6)
    /// Less patience for a model that has recently been slow to speak.
    static let slowModelHedgeDelay: Duration = .seconds(3)
    /// Slow first tokens in the current window that earn the shorter delay.
    static let slowSamplesForShortHedge = 2

    func hedgeDelay(for model: String) async -> Duration {
        health.slowFirstTokenSamples(model) >= Self.slowSamplesForShortHedge
            ? Self.slowModelHedgeDelay
            : Self.hedgeDelay
    }

    /// The next-ranked healthy model on the same provider. The provider is the user's
    /// trust boundary; a race never hands a sensitive turn to a stranger.
    func hedgeCandidate(after model: String, request: RouteRequest) async -> ResolvedRoute? {
        guard request.isAuto, let provider = request.currentProvider else { return nil }
        // A hedge races for the same turn, so it keeps the turn's tier: the primary
        // model's tier, or reasoning when the message scored complex.
        let candidates = rankedCandidates(
            for: request, provider: provider, at: now(),
            needsReasoning: QueryComplexity.needsReasoning(text: request.lastUserMessage ?? "")
                || KnownModelCatalog.lookup(model)?.supportsReasoning == true
        )
        guard let runnerUp = candidates.first(where: { $0 != model }) else { return nil }
        AppLogger.debug(
            "Hedge runner-up for \(public: model) on \(public: provider.name): \(public: runnerUp)",
            category: .routing
        )
        return ResolvedRoute(
            providerID: provider.id, baseURL: provider.baseURL, model: runnerUp, change: nil
        )
    }

    /// A hedge loser stayed silent past its runner-up: a hang. Two consecutive
    /// losses quarantine immediately (doubling backoff); one loss stays a
    /// sample, so a blip never sides against a healthier-ranked model.
    func recordHedgeLoss(_ model: String, silentFor: Duration) async {
        let timestamp = now()
        AppLogger.info(
            "Hedge: \(public: model) silent for \(public: format(silentFor)); its runner-up spoke first",
            category: .routing
        )
        health.markActivity(now: timestamp)
        health.recordSample(
            model, wasSlowFirstToken: true, wasSlowThroughput: false, now: timestamp
        )
        // The 2nd loss benches. Quarantine clears the sample window, so the
        // count restarts on the next probe - if it repeats, the standing
        // backoff doubles the bench.
        guard health.slowFirstTokenSamples(model) >= Self.slowSamplesForShortHedge else {
            return
        }
        let degradation = DegradationReason.slowFirstToken
        let until = health.quarantine(
            model, now: timestamp, base: ModelHealthStore.slownessQuarantine
        )
        AppLogger.info(
            "Quarantining \(public: model) until \(public: format(until)): \(public: String(describing: degradation))",
            category: .routing
        )
    }
}
