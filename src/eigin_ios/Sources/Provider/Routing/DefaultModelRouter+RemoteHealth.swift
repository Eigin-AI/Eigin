import Foundation

extension DefaultModelRouter {
    struct EvidenceKey: Hashable {
        let providerID: UUID
        let model: String
    }

    /// Timestamps for comparing local observations with remote samples.
    struct LocalHealthRecency {
        let observedAt: Date
        let ttftObservedAt: Date?
        let tpsObservedAt: Date?
    }

    struct MetricEvidence {
        let value: Double
        let observedAt: Date
        let expiresAt: Date
    }

    struct SharedDegradation {
        var ttft: MetricEvidence?
        var tps: MetricEvidence?
    }

    /// Applies app health policy independently to each fresh shared measurement.
    func remoteDegradation(
        _ model: String,
        provider: RoutingProvider,
        at timestamp: Date
    ) -> DegradationReason? {
        let key = EvidenceKey(providerID: provider.id, model: model)
        guard let health = remoteHealthByProvider[provider.id]?[model] else {
            remoteDegradations[key] = nil
            return nil
        }
        let ttft = newestEligibleSample(health.ttft, minimum: 3, at: timestamp)
        let tps = newestEligibleSample(health.tps, minimum: 3, at: timestamp)
        let failures = newestEligibleSample(health.failures, minimum: 4, at: timestamp)
        let local = localHealthRecency[key]
        var degradation = remoteDegradations[key] ?? SharedDegradation()
        degradation.ttft = updatedDegradation(
            degradation.ttft,
            with: ttft,
            local: local?.ttftObservedAt,
            bad: { $0 > 10000 },
            recovered: { $0 < 8000 },
            at: timestamp
        )
        degradation.tps = updatedDegradation(
            degradation.tps,
            with: tps,
            local: local?.tpsObservedAt,
            bad: { $0 < 5 },
            recovered: { $0 > 6 },
            at: timestamp
        )
        remoteDegradations[key] = degradation
        if let failures, failures.value >= 0.5,
           !(local.map { $0.observedAt > failures.observedAt } ?? false) { return .errors }
        if degradation.ttft != nil { return .slowFirstToken }
        if degradation.tps != nil { return .slowThroughput }
        return nil
    }

    private func newestEligibleSample(
        _ samples: [RemoteHealthSample],
        minimum: Int,
        at timestamp: Date
    ) -> MetricEvidence? {
        samples.filter {
            $0.expiresAt > timestamp && $0.observedAt <= timestamp
                && $0.count >= ($0.source == .probe ? 1 : minimum)
        }.max { $0.observedAt < $1.observedAt }.map {
            MetricEvidence(value: $0.value, observedAt: $0.observedAt, expiresAt: $0.expiresAt)
        }
    }

    private func updatedDegradation(
        _ previous: MetricEvidence?,
        with evidence: MetricEvidence?,
        local: Date?,
        bad: (Double) -> Bool,
        recovered: (Double) -> Bool,
        at timestamp: Date
    ) -> MetricEvidence? {
        var current = previous.flatMap { $0.expiresAt > timestamp ? $0 : nil }
        if let evidence,
           current.map({ evidence.observedAt > $0.observedAt }) ?? true
        {
            if bad(evidence.value) { current = evidence }
            else if recovered(evidence.value) { current = nil }
        }
        // Newer local evidence delegates to the existing local sample/quarantine policy.
        if let local, let retained = current,
           local > retained.observedAt { current = nil }
        return current
    }
}
