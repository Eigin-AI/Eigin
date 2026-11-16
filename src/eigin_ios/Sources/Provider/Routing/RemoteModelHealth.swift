import Foundation

/// Provider-neutral remote observations, read without network work during routing.
protocol RemoteModelHealthSource: Sendable {
    /// Uses a persistence-free provider snapshot to select applicable observations.
    func health(for provider: RoutingProvider) async -> [String: RemoteModelHealth]
}

/// Independent evidence for failures, first useful output, and output rate.
struct RemoteModelHealth: Sendable {
    var failures: [RemoteHealthSample] = []
    var ttft: [RemoteHealthSample] = []
    var tps: [RemoteHealthSample] = []
}

/// A measured value with its sample size, origin, and observation lifetime.
struct RemoteHealthSample: Sendable {
    enum Source: Sendable { case requests, probe }
    let value: Double
    let count: Int
    let source: Source
    let observedAt: Date
    let expiresAt: Date
}
