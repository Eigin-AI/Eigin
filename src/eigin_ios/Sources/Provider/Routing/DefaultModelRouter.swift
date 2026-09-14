import Foundation

/// ``ModelRouter`` backed by ``KnownModelCatalog`` rankings and in-session health.
///
/// Thresholds below are estimates and want tuning against real traffic.
actor DefaultModelRouter: ModelRouter {
    /// No first token by here is indistinguishable from a hang, so the attempt counts as
    /// a failure and another model gets a turn.
    static let firstTokenCeiling: Duration = .seconds(30)
    /// Above this, a model is working but unpleasant to wait for.
    static let slowFirstTokenThreshold: Duration = .seconds(10)
    /// Below this, generation is crawling even if it started promptly.
    static let slowThroughputThreshold: Double = 5
    /// Output room assumed for a model the catalog gives no figure for.
    static let assumedOutputReserve = 256

    private var health = ModelHealthStore()
    /// Set when a request fails as offline, since a satisfied path can still be a dead
    /// uplink. Cleared by a successful route or by the path coming back.
    private var sawOfflineFailure = false
    private var wasReachable = true

    private let reachability: any NetworkReachability
    private let localModelReadiness: @Sendable () -> Bool
    private let now: @Sendable () -> Date

    init(
        reachability: any NetworkReachability,
        localModelReadiness: @escaping @Sendable () -> Bool,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.reachability = reachability
        self.localModelReadiness = localModelReadiness
        self.now = now
    }

    // MARK: - Resolve

    /// The routing policy, in order:
    ///
    /// 1. A pinned model is left alone, offline included. That user opted out of us
    ///    choosing, so choosing for them anyway would break the promise.
    /// 2. Offline goes to the on-device model, if there is a ready one.
    /// 3. A new session climbs back to the top of the ranking.
    /// 4. A healthy model keeps the turn, protecting the provider's prompt cache.
    /// 5. Otherwise take the best of what is left.
    func resolve(_ request: RouteRequest) async -> ResolvedRoute {
        let timestamp = now()
        noteReachability()

        guard request.isAuto, let provider = request.currentProvider else {
            return stayPut(request)
        }
        if let offline = offlineRoute(for: request, at: timestamp) {
            return offline
        }

        let openedNewSession = health.openSessionIfIdle(at: timestamp)
        let candidates = rankedCandidates(for: request, provider: provider, at: timestamp)

        guard let preferred = candidates.first else {
            AppLogger.warning(
                "No candidate model on \(public: provider.name) meets the turn's needs; staying on \(public: request.currentModel)",
                category: .routing
            )
            return stayPut(request)
        }
        if openedNewSession {
            return climbBack(to: preferred, request: request, provider: provider)
        }
        if candidates.contains(request.currentModel) {
            AppLogger.debug(
                "Staying on \(public: request.currentModel) (\(public: candidates.count) candidates healthy)",
                category: .routing
            )
            return stayPut(request)
        }
        return switchAway(to: preferred, request: request, provider: provider)
    }

    /// A cold cache is nothing to protect, so a new session returns to the best model.
    private func climbBack(
        to preferred: String, request: RouteRequest, provider: RoutingProvider
    ) -> ResolvedRoute {
        guard preferred != request.currentModel else {
            AppLogger.info(
                "Session reset; \(public: preferred) is already the preferred model",
                category: .routing
            )
            return stayPut(request)
        }
        AppLogger.info(
            "Session reset after idle; returning to \(public: preferred) from \(public: request.currentModel)",
            category: .routing
        )
        return route(
            to: preferred, on: provider,
            change: .sessionReset(previous: request.currentModel)
        )
    }

    /// The current model is no longer a candidate, so the turn moves on.
    private func switchAway(
        to preferred: String, request: RouteRequest, provider: RoutingProvider
    ) -> ResolvedRoute {
        let change = changeReason(leaving: request.currentModel, provider: provider)
        AppLogger.info(
            "Routing \(public: request.currentModel) -> \(public: preferred) on \(public: provider.name): \(public: describe(change)). Set aside: \(public: sidelined(on: provider))",
            category: .routing
        )
        return route(to: preferred, on: provider, change: change)
    }

    // MARK: - Retry

    /// After a failed attempt, the next model worth trying on the same provider.
    ///
    /// Two requirements are firmer here than on a fresh turn. The prompt is already built
    /// and compaction cannot run again, so the window is not negotiable; and health is not
    /// relaxed, since the point is to get off the model that just failed.
    func retry(after error: Error, request: RouteRequest) async -> ResolvedRoute? {
        let failure = RoutingFailure(from: error)
        let timestamp = now()

        guard request.isAuto, let provider = request.currentProvider else { return nil }
        guard failure.blamesModel else {
            AppLogger.debug(
                "Not retrying \(public: request.currentModel): failure is not the model's to answer for",
                category: .routing
            )
            return nil
        }

        apply(failure: failure, to: request.currentModel, at: timestamp)

        let candidates = rankedCandidates(
            for: request,
            provider: provider,
            at: timestamp,
            relaxing: [.vision],
            relaxHealth: false
        )
        guard let next = candidates.first(where: { $0 != request.currentModel }) else {
            AppLogger.warning(
                "No usable alternative to \(public: request.currentModel) on \(public: provider.name); surfacing the error",
                category: .routing
            )
            return nil
        }

        let change = changeReason(leaving: request.currentModel, provider: provider)
        AppLogger.info(
            "Retrying on \(public: next) after \(public: request.currentModel) failed (\(public: String(describing: failure)))",
            category: .routing
        )
        return route(to: next, on: provider, change: change)
    }

    // MARK: - Record

    func record(_ attempt: AttemptOutcome) async {
        let timestamp = now()
        switch attempt.result {
        case .cancelled:
            return
        case .failed(let failure):
            recordFailure(failure, attempt: attempt, at: timestamp)
        case .succeeded:
            recordSuccess(attempt, at: timestamp)
        }
    }

    private func recordFailure(
        _ failure: RoutingFailure, attempt: AttemptOutcome, at timestamp: Date
    ) {
        if case .offline = failure { sawOfflineFailure = true }
        AppLogger.info(
            "Attempt on \(public: attempt.model) failed: \(public: String(describing: failure)) after \(public: format(attempt.duration))",
            category: .routing
        )
        guard failure.blamesModel else { return }
        apply(failure: failure, to: attempt.model, at: timestamp)
    }

    /// A working stream still demotes a model that is consistently unpleasant to wait
    /// for, but only after a pattern. One slow turn is noise.
    private func recordSuccess(_ attempt: AttemptOutcome, at timestamp: Date) {
        sawOfflineFailure = false
        let slowFirstToken = (attempt.timeToFirstToken ?? .zero) > Self.slowFirstTokenThreshold
        let slowThroughput = attempt.tokensPerSecond.map { $0 < Self.slowThroughputThreshold }
            ?? false
        AppLogger.debug(
            "Attempt on \(public: attempt.model) succeeded: ttft \(public: format(attempt.timeToFirstToken)), \(public: format(attempt.tokensPerSecond)) tok/s",
            category: .routing
        )
        health.recordSuccess(attempt.model, now: timestamp)
        let degradation = health.recordSample(
            attempt.model,
            wasSlowFirstToken: slowFirstToken,
            wasSlowThroughput: slowThroughput,
            now: timestamp
        )
        guard let degradation else { return }
        let until = health.quarantine(
            attempt.model, now: timestamp, base: ModelHealthStore.slownessQuarantine
        )
        AppLogger.info(
            "Quarantining \(public: attempt.model) until \(public: format(until)): \(public: String(describing: degradation)) (ttft \(public: format(attempt.timeToFirstToken)) vs \(public: format(Self.slowFirstTokenThreshold)), \(public: format(attempt.tokensPerSecond)) vs \(public: Self.slowThroughputThreshold) tok/s)",
            category: .routing
        )
    }

    // MARK: - Capability

    func canSatisfy(_ request: RouteRequest) async -> Bool {
        guard let provider = request.currentProvider else { return false }
        guard request.isAuto else {
            return meets(request.currentModel, requirements: request.requirements)
        }
        return !rankedCandidates(
            for: request, provider: provider, at: now(), relaxing: []
        ).isEmpty
    }

    // MARK: - Offline

    /// The on-device model, when there is no usable network and a ready one to fall to.
    ///
    /// Two signals, because a satisfied path does not prove the internet is reachable:
    /// the path monitor, and a request that already failed as offline.
    private func offlineRoute(for request: RouteRequest, at timestamp: Date) -> ResolvedRoute? {
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
    private func noteReachability() {
        let reachable = reachability.isReachable
        defer { wasReachable = reachable }
        guard reachable, !wasReachable else { return }
        sawOfflineFailure = false
    }

    // MARK: - Candidates

    /// The pool Auto routing chooses from: the user's enabled models that the provider
    /// still serves, falling back to the full fetched catalogue when nothing is enabled
    /// (a legacy provider seeded before the field). One gate for both candidate
    /// selection and the offline/local fallback, so a disabled model never returns
    /// through health.
    private func offer(for provider: RoutingProvider) -> [String] {
        guard !provider.enabledModels.isEmpty else { return provider.availableModels }
        let served = Set(provider.availableModels)
        return provider.enabledModels.filter { served.contains($0) }
    }

    /// A requirement the router is willing to give up, in the order it gives them up.
    ///
    /// Vision goes first: the pipeline strips the images and tells the model it cannot
    /// see, which is a worse answer but still an answer. The window goes next, and only
    /// where compaction can still resize the prompt. Tool calling never appears here,
    /// because a model that cannot call tools cannot be this agent.
    private enum Concession {
        case vision
        case contextWindow
    }

    /// Models on `provider` that could run the turn, best first.
    ///
    /// Each concession in `relaxing` is dropped in turn until something matches. If
    /// nothing does, quarantined models are tried anyway: a known-flaky model beats
    /// refusing to answer. Retired ones stay out, since the provider does not serve them.
    private func rankedCandidates(
        for request: RouteRequest,
        provider: RoutingProvider,
        at timestamp: Date,
        relaxing concessions: [Concession] = [.vision, .contextWindow],
        relaxHealth: Bool = true
    ) -> [String] {
        let ranked = KnownModelCatalog.knownModels(in: offer(for: provider))
            .sorted { rank(of: $0) < rank(of: $1) }

        let ladder = relaxationLadder(from: request.requirements, conceding: concessions)

        for (step, relaxed) in ladder.enumerated() {
            let matches = ranked.filter {
                meets($0, requirements: relaxed) && health.isHealthy($0, now: timestamp)
            }
            guard !matches.isEmpty else { continue }
            if step > 0 {
                AppLogger.info(
                    "Relaxed routing requirements on \(public: provider.name) to reach \(public: matches[0]): vision \(public: relaxed.needsVision), prompt \(public: relaxed.promptTokens ?? 0) tokens",
                    category: .routing
                )
            }
            return matches
        }

        guard relaxHealth, let loosest = ladder.last else { return [] }
        let ignoringHealth = ranked.filter {
            meets($0, requirements: loosest) && !health.isRetired($0)
        }
        if !ignoringHealth.isEmpty {
            AppLogger.warning(
                "Every candidate on \(public: provider.name) is quarantined; trying \(public: ignoringHealth[0]) anyway",
                category: .routing
            )
        }
        return ignoringHealth
    }

    /// The requirement sets to try, strictest first.
    private func relaxationLadder(
        from requirements: RouteRequirements, conceding concessions: [Concession]
    ) -> [RouteRequirements] {
        var ladder = [requirements]
        for concession in concessions {
            var relaxed = ladder[ladder.count - 1]
            switch concession {
            case .vision:
                guard relaxed.needsVision else { continue }
                relaxed.needsVision = false
            case .contextWindow:
                guard relaxed.promptTokens != nil else { continue }
                relaxed.promptTokens = nil
            }
            ladder.append(relaxed)
        }
        return ladder
    }

    /// Whether one model clears the bar.
    ///
    /// The window check reserves the candidate's *own* output allowance, so a small model
    /// is judged against what it can actually do rather than a flat figure it could never
    /// clear.
    private func meets(_ model: String, requirements: RouteRequirements) -> Bool {
        guard let entry = KnownModelCatalog.lookup(model) else { return false }
        if requirements.needsToolCalling, !entry.supportsToolCall { return false }
        if requirements.needsVision, !entry.supportsVision { return false }
        if let promptTokens = requirements.promptTokens {
            let reserve = entry.maxOutput ?? Self.assumedOutputReserve
            if entry.contextWindow < promptTokens + reserve { return false }
        }
        return true
    }

    private func rank(of model: String) -> Int {
        guard let pattern = KnownModelCatalog.lookup(model)?.pattern,
              let index = KnownModelCatalog.preferenceRanking.firstIndex(of: pattern)
        else {
            return .max
        }
        return index
    }

    // MARK: - Health

    private func apply(failure: RoutingFailure, to model: String, at timestamp: Date) {
        switch failure {
        case .modelNotFound:
            health.markRetired(model, now: timestamp)
            AppLogger.info(
                "\(public: model) is gone from the provider's catalog; retired for this session",
                category: .routing
            )
        case .providerOverloaded, .timedOut:
            let until = health.quarantine(
                model, now: timestamp, base: ModelHealthStore.baseQuarantine
            )
            AppLogger.info(
                "Quarantining \(public: model) until \(public: format(until)): \(public: String(describing: failure))",
                category: .routing
            )
        case .offline, .notTheModelsFault:
            break
        }
    }

    // MARK: - Hedge

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
        let candidates = rankedCandidates(for: request, provider: provider, at: now())
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

    private func changeReason(leaving model: String, provider: RoutingProvider) -> RouteChange {
        if !provider.availableModels.contains(model) || health.isRetired(model) {
            return .modelRetired(previous: model)
        }
        return .modelDegraded(previous: model, reason: .errors)
    }

    // MARK: - Helpers

    private func stayPut(_ request: RouteRequest) -> ResolvedRoute {
        ResolvedRoute(
            providerID: request.currentProviderID,
            baseURL: request.currentProvider?.baseURL ?? "",
            model: request.currentModel,
            change: nil
        )
    }

    private func route(
        to model: String, on provider: RoutingProvider, change: RouteChange
    ) -> ResolvedRoute {
        ResolvedRoute(
            providerID: provider.id,
            baseURL: provider.baseURL,
            model: model,
            change: change
        )
    }

    /// The models currently unavailable to routing, and why. The single most useful line
    /// when working out from a log why the agent ended up where it did.
    private func sidelined(on provider: RoutingProvider) -> String {
        let reasons = provider.availableModels.compactMap { model -> String? in
            guard let reason = health.quarantineReason(model) else { return nil }
            return "\(model) (\(reason))"
        }
        return reasons.isEmpty ? "none" : reasons.joined(separator: ", ")
    }

    private func describe(_ change: RouteChange) -> String {
        switch change {
        case .offlineFallback: "offline"
        case .modelRetired: "retired"
        case .modelDegraded(_, let reason): "degraded (\(reason))"
        case .sessionReset: "session reset"
        }
    }

    private func format(_ duration: Duration?) -> String {
        guard let duration else { return "n/a" }
        let seconds = Double(duration.components.seconds)
            + Double(duration.components.attoseconds) / 1e18
        return String(format: "%.2fs", seconds)
    }

    private func format(_ value: Double?) -> String {
        guard let value else { return "n/a" }
        return String(format: "%.1f", value)
    }

    private func format(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .standard)
    }
}
