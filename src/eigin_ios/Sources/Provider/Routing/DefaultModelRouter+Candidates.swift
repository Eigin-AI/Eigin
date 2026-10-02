import Foundation

// MARK: - Candidate selection

extension DefaultModelRouter {
    /// The pool Auto routing chooses from: the user's enabled models that the provider
    /// still serves, falling back to the full fetched catalogue when nothing is enabled
    /// (a legacy provider seeded before the field). One gate for both candidate
    /// selection and the offline/local fallback, so a disabled model never returns
    /// through health.
    func offer(for provider: RoutingProvider) -> [String] {
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
    enum Concession {
        case vision
        case contextWindow
    }

    /// Models on `provider` that could run the turn, best first.
    ///
    /// Ordered by the turn's complexity tier before preference: simple turns prefer
    /// non-reasoning models (fast), complex ones prefer reasoning models (careful), with
    /// `preferenceRanking` breaking ties inside a tier. Both tiers always stay in the
    /// list — the provider may only serve one tier, and a tier-inferior model must
    /// remain a candidate so in-conversation stickiness can hold it.
    ///
    /// Each concession in `relaxing` is dropped in turn until something matches. If
    /// nothing does, quarantined models are tried anyway: a known-flaky model beats
    /// refusing to answer. Retired ones stay out, since the provider does not serve them.
    func rankedCandidates(
        for request: RouteRequest,
        provider: RoutingProvider,
        at timestamp: Date,
        needsReasoning: Bool,
        relaxing concessions: [Concession] = [.vision, .contextWindow],
        relaxHealth: Bool = true
    ) -> [String] {
        let ranked = KnownModelCatalog.knownModels(in: offer(for: provider))
            .sorted { a, b in
                let (aTier, bTier) = (
                    tierOrder(of: a, wantsReasoning: needsReasoning),
                    tierOrder(of: b, wantsReasoning: needsReasoning)
                )
                if aTier != bTier { return aTier < bTier }
                return rank(of: a) < rank(of: b)
            }

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
    func meets(_ model: String, requirements: RouteRequirements) -> Bool {
        guard let entry = KnownModelCatalog.lookup(model) else { return false }
        if requirements.needsToolCalling, !entry.supportsToolCall { return false }
        if requirements.needsVision, !entry.supportsVision { return false }
        if let promptTokens = requirements.promptTokens {
            let reserve = entry.maxOutput ?? Self.assumedOutputReserve
            if entry.contextWindow < promptTokens + reserve { return false }
        }
        return true
    }

    func rank(of model: String) -> Int {
        guard let pattern = KnownModelCatalog.lookup(model)?.pattern,
              let index = KnownModelCatalog.preferenceRanking.firstIndex(of: pattern)
        else {
            return .max
        }
        return index
    }

    /// Where a model sits in the turn's tier ordering: 0 is the tier the turn wants,
    /// 1 the one it will settle for. Unknown-to-catalog models are treated as
    /// non-reasoning, matching their bottom-of-the-ranking treatment.
    private func tierOrder(of model: String, wantsReasoning: Bool) -> Int {
        let isReasoning = KnownModelCatalog.lookup(model)?.supportsReasoning ?? false
        return isReasoning == wantsReasoning ? 0 : 1
    }

    /// Whether a model can serve the turn's complexity tier. A simple turn is served
    /// by anything — which is what makes the step-up lock work: a reasoning model
    /// answers simple follow-ups without the conversation stepping back down.
    func satisfiesTier(_ model: String, needsReasoning: Bool) -> Bool {
        guard needsReasoning else { return true }
        return KnownModelCatalog.lookup(model)?.supportsReasoning == true
    }
}
