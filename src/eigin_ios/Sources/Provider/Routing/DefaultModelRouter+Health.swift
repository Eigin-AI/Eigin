import Foundation

// MARK: - Model health recording

extension DefaultModelRouter {
    /// Combines local quarantine and applicable remote observations.
    func isHealthy(_ model: String, provider: RoutingProvider, at timestamp: Date) -> Bool {
        health.isHealthy(model, now: timestamp)
            && remoteDegradation(model, provider: provider, at: timestamp) == nil
    }

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
        let key = EvidenceKey(providerID: attempt.providerID, model: attempt.model)
        let previous = localHealthRecency[key]
        localHealthRecency[key] = LocalHealthRecency(
            observedAt: timestamp,
            ttftObservedAt: attempt.timeToFirstToken.map { _ in timestamp } ?? previous?
                .ttftObservedAt,
            tpsObservedAt: attempt.tokensPerSecond.map { _ in timestamp } ?? previous?.tpsObservedAt
        )
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

    func apply(failure: RoutingFailure, to model: String, at timestamp: Date) {
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
}
