import Foundation

/// ``ModelRouter`` backed by ``KnownModelCatalog`` rankings and in-session health.
///
/// The routing logic is split across extensions: selection and failover live here,
/// offline handling, model health, candidates, and hedging in their own files.
actor DefaultModelRouter: ModelRouter {
    /// No first token by here is indistinguishable from a hang, so the attempt counts as
    /// a failure and another model gets a turn. The worst fully silent turn is two
    /// ceilings — first expiry chases once, a silent chase fails on the rearmed
    /// ceiling — so the user waits at most ~40s before the timeout card.
    static let firstTokenCeiling: Duration = .seconds(20)
    /// Above this, a model is working but unpleasant to wait for.
    static let slowFirstTokenThreshold: Duration = .seconds(10)
    /// Below this, generation is crawling even if it started promptly.
    static let slowThroughputThreshold: Double = 5
    /// Output room assumed for a model the catalog gives no figure for.
    static let assumedOutputReserve = 256

    var health = ModelHealthStore()
    /// The model each conversation last routed to, so stickiness anchors per
    /// conversation instead of globally on the agent. Cleared on a session reset:
    /// after a long idle the provider's prompt cache is cold, so restarting every
    /// conversation on the fast tier costs nothing. In-memory only — after a
    /// relaunch, conversations anchor on `agent.model` until their next turn.
    var lastModelByConversation: [UUID: String] = [:]
    var sawOfflineFailure = false
    var wasReachable = true

    let reachability: any NetworkReachability
    let localModelReadiness: @Sendable () -> Bool
    let now: @Sendable () -> Date

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
    /// 3. A new session — or a conversation we have never routed before — climbs back
    ///    to the top of the tier its message asks for, so conversations start fast.
    /// 4. A healthy model that satisfies the turn's complexity tier keeps the turn,
    ///    protecting the conversation's prompt cache. This is where the step-up lock
    ///    lives: a reasoning model stays even when the next message scores simple.
    /// 5. Otherwise take the best of what is left — including stepping up to a
    ///    reasoning model when the message scored complex.
    func resolve(_ request: RouteRequest) async -> ResolvedRoute {
        let timestamp = now()
        noteReachability()
        let messageNeedsReasoning = QueryComplexity.needsReasoning(
            text: request.lastUserMessage ?? ""
        )

        guard request.isAuto, let provider = request.currentProvider else {
            return storingAnchor(sameRoute(for: request), for: request)
        }
        if let offline = offlineRoute(for: request, at: timestamp) {
            return storingAnchor(offline, for: request)
        }

        let openedNewSession = health.openSessionIfIdle(at: timestamp)
        if openedNewSession {
            // Clear the memory first: the reset turn is judged by the message alone,
            // so every conversation — locked or not — restarts on the fast tier.
            lastModelByConversation.removeAll()
        }
        let conversationIsNew = neverRouted(request.conversationID)
        let anchor = conversationAnchor(for: request)
        // A conversation already locked into reasoning keeps that tier on forced
        // switches (an image arriving, say); fresh conversations go by the message.
        let wantsReasoning = messageNeedsReasoning
            || (request.conversationID != nil && !conversationIsNew
                && KnownModelCatalog.lookup(anchor)?.supportsReasoning == true)
        let candidates = rankedCandidates(
            for: request, provider: provider, at: timestamp, needsReasoning: wantsReasoning
        )

        guard let preferred = candidates.first else {
            AppLogger.warning(
                "No candidate model on \(public: provider.name) meets the turn's needs; staying on \(public: request.currentModel)",
                category: .routing
            )
            return storingAnchor(sameRoute(for: request), for: request)
        }
        if openedNewSession {
            return storingAnchor(
                climbBack(
                    to: preferred, from: anchor, request: request, provider: provider,
                    reason: "Idle session reset"
                ),
                for: request
            )
        }
        if conversationIsNew {
            return storingAnchor(
                climbBack(
                    to: preferred, from: anchor, request: request, provider: provider,
                    reason: "Fresh conversation"
                ),
                for: request
            )
        }
        // The step-up lock: a conversation's own model keeps the turn unless the
        // message needs reasoning and the model cannot provide it.
        if candidates.contains(anchor),
           satisfiesTier(anchor, needsReasoning: messageNeedsReasoning)
        {
            AppLogger.debug(
                "Staying on \(public: anchor) (\(public: candidates.count) candidates healthy)",
                category: .routing
            )
            return storingAnchor(anchorRoute(to: anchor, on: provider), for: request)
        }
        return storingAnchor(
            switchAway(
                to: preferred, from: anchor, request: request, provider: provider,
                needsReasoning: messageNeedsReasoning
            ),
            for: request
        )
    }

    /// The model this conversation's stickiness is judged against: its own last
    /// routed model, or the agent's model before the router has ever seen it.
    func conversationAnchor(for request: RouteRequest) -> String {
        guard let id = request.conversationID, let last = lastModelByConversation[id] else {
            return request.currentModel
        }
        return last
    }

    /// True when the router has no memory of this conversation yet.
    func neverRouted(_ conversationID: UUID?) -> Bool {
        guard let id = conversationID else { return false }
        return lastModelByConversation[id] == nil
    }

    /// Stores the conversation's routed model so its next turn anchors there.
    /// Routes that left the conversation's provider (an offline detour) are not
    /// remembered: the anchor would not exist among the cloud candidates anyway.
    func storingAnchor(_ route: ResolvedRoute, for request: RouteRequest) -> ResolvedRoute {
        if let id = request.conversationID, request.isAuto,
           route.providerID == request.currentProviderID
        {
            lastModelByConversation[id] = route.model
        }
        return route
    }

    /// A cold cache is nothing to protect, so a fresh session or conversation returns
    /// to the best model of the turn's tier.
    private func climbBack(
        to preferred: String, from anchor: String, request: RouteRequest,
        provider: RoutingProvider, reason: String
    ) -> ResolvedRoute {
        guard preferred != anchor else {
            AppLogger.info(
                "\(public: reason); \(public: preferred) is already the preferred model",
                category: .routing
            )
            return anchorRoute(to: anchor, on: provider)
        }
        AppLogger.info(
            "\(public: reason); returning to \(public: preferred) from \(public: anchor)",
            category: .routing
        )
        return route(
            to: preferred, on: provider,
            change: .sessionReset(previous: anchor)
        )
    }

    /// The current model no longer fits the turn's tier, so the conversation moves.
    /// When the model is healthy but cannot provide the reasoning the message needs,
    /// that is a step up, not a degradation — and the log (and UI, one day) should
    /// tell the two apart.
    private func switchAway(
        to preferred: String, from anchor: String, request: RouteRequest,
        provider: RoutingProvider, needsReasoning: Bool
    ) -> ResolvedRoute {
        let steppedUp = needsReasoning
            && KnownModelCatalog.lookup(anchor)?.supportsReasoning == false
            && health.isHealthy(anchor, now: now())
        let change: RouteChange = steppedUp
            ? .steppedUp(previous: anchor)
            : changeReason(leaving: anchor, provider: provider)
        AppLogger.info(
            "Routing \(public: anchor) -> \(public: preferred) on \(public: provider.name): \(public: describe(change)). Set aside: \(public: sidelined(on: provider))",
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
    ///
    /// Complexity survives the failure: a complex turn that fails on its reasoning model
    /// prefers another reasoning model, but cascades down to a non-reasoning one rather
    /// than answer nothing — failover is the safety net under the tier choice.
    func retry(after error: Error, request: RouteRequest) async -> ResolvedRoute? {
        let failure = RoutingFailure(from: error)
        let timestamp = now()
        let needsReasoning = QueryComplexity.needsReasoning(text: request.lastUserMessage ?? "")
            || KnownModelCatalog.lookup(request.currentModel)?.supportsReasoning == true

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
            needsReasoning: needsReasoning,
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
        return storingAnchor(
            route(to: next, on: provider, change: change), for: request
        )
    }

    // MARK: - Capability

    func canSatisfy(_ request: RouteRequest) async -> Bool {
        guard let provider = request.currentProvider else { return false }
        guard request.isAuto else {
            return meets(request.currentModel, requirements: request.requirements)
        }
        return !rankedCandidates(
            for: request, provider: provider, at: now(),
            needsReasoning: false, relaxing: []
        ).isEmpty
    }

    // MARK: - Change reasons

    func changeReason(
        leaving model: String, provider: RoutingProvider
    ) -> RouteChange {
        if !provider.availableModels.contains(model) || health.isRetired(model) {
            return .modelRetired(previous: model)
        }
        return .modelDegraded(previous: model, reason: .errors)
    }

    // MARK: - Routes

    /// The route for staying exactly where the agent is.
    private func sameRoute(for request: RouteRequest) -> ResolvedRoute {
        ResolvedRoute(
            providerID: request.currentProviderID,
            baseURL: request.currentProvider?.baseURL ?? "",
            model: request.currentModel,
            change: nil
        )
    }

    /// A keep-the-turn route anchored to `model` — the conversation's own model,
    /// which may differ from `request.currentModel` (the agent's global model).
    private func anchorRoute(to model: String, on provider: RoutingProvider) -> ResolvedRoute {
        ResolvedRoute(
            providerID: provider.id,
            baseURL: provider.baseURL,
            model: model,
            change: nil
        )
    }

    func route(
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
    func sidelined(on provider: RoutingProvider) -> String {
        let reasons = provider.availableModels.compactMap { model -> String? in
            guard let reason = health.quarantineReason(model) else { return nil }
            return "\(model) (\(reason))"
        }
        return reasons.isEmpty ? "none" : reasons.joined(separator: ", ")
    }

    func describe(_ change: RouteChange) -> String {
        switch change {
        case .offlineFallback: "offline"
        case .modelRetired: "retired"
        case .modelDegraded(_, let reason): "degraded (\(reason))"
        case .sessionReset: "session reset"
        case .steppedUp: "stepped up to reasoning"
        }
    }

    func format(_ duration: Duration?) -> String {
        guard let duration else { return "n/a" }
        let seconds = Double(duration.components.seconds)
            + Double(duration.components.attoseconds) / 1e18
        return String(format: "%.2fs", seconds)
    }

    func format(_ value: Double?) -> String {
        guard let value else { return "n/a" }
        return String(format: "%.1f", value)
    }

    func format(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .standard)
    }
}
