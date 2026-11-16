import Foundation

extension RelayModelStatusSnapshot {
    /// Translate relay fields and server timestamps into device-local observations.
    func health(for provider: RoutingProvider) -> [String: RemoteModelHealth] {
        guard ProviderPreset.isRelay(provider.baseURL) else { return [:] }
        var result: [String: RemoteModelHealth] = [:]
        for model in response.models {
            var health = RemoteModelHealth()
            for (summary, source) in [
                (model.traffic, RemoteHealthSample.Source.requests),
                (model.probes, .probe),
            ] {
                guard let summary else { continue }
                func sample(_ value: Double?, date: Date?, count: Int) -> RemoteHealthSample? {
                    guard let value, let date, date <= summary.sampledAt,
                          value.isFinite else { return nil }
                    return RemoteHealthSample(
                        value: value,
                        count: count,
                        source: source,
                        observedAt: deviceDate(date),
                        expiresAt: deviceDate(summary.expiresAt)
                    )
                }
                let count = summary.successCount.addingReportingOverflow(summary.failureCount)
                if !count.overflow, count.partialValue > 0,
                   let value = sample(
                       Double(summary.failureCount) / Double(count.partialValue),
                       date: summary.sampledAt,
                       count: count.partialValue
                   )
                {
                    health.failures.append(value)
                }
                if let value = sample(
                    summary.ttft,
                    date: summary.ttftSampledAt,
                    count: summary.ttftSampleCount
                ) { health.ttft.append(value) }
                if let value = sample(
                    summary.tps,
                    date: summary.tpsSampledAt,
                    count: summary.throughputSampleCount
                ) { health.tps.append(value) }
            }
            result[model.id] = health
        }
        return result
    }
}
