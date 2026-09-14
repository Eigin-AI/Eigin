import Foundation

/// Per-model health for one session, plus the session clock itself.
///
/// State is in-memory and per-launch by design: only the resolved model is persisted, on
/// the agent. Routing state is transient and cheap to change, so it earns no schema.
struct ModelHealthStore {
    /// Idle gap after which health is cleared and preference resets to the top.
    ///
    /// Stickiness exists to protect prompt caches, and those are ephemeral. After an hour
    /// idle there is no cache left to protect, so a model demoted by an intermittent
    /// problem gets another chance rather than degrading the agent forever.
    static let sessionIdleTimeout: Duration = .seconds(60 * 60)

    /// First quarantine length for a model the provider is struggling to serve. Doubles
    /// on repeat, up to ``maxQuarantine``.
    static let baseQuarantine: Duration = .seconds(5 * 60)
    static let maxQuarantine: Duration = .seconds(60 * 60)
    /// Slowness is a weaker signal than an error, so it steps aside for less time.
    static let slownessQuarantine: Duration = .seconds(2 * 60)

    private var entries: [String: Entry] = [:]
    private var lastActivity: Date?

    struct Entry {
        var quarantinedUntil: Date?
        /// Survives quarantine expiry so a repeatedly bad model backs off further.
        var consecutiveQuarantines: Int = 0
        /// Set for a model the provider no longer lists, which no expiry should undo.
        var retiredForSession: Bool = false
        var recentSamples: [Sample] = []
    }

    struct Sample {
        let wasSlowFirstToken: Bool
        let wasSlowThroughput: Bool
    }

    /// Samples kept per model, and how many must be slow before demoting it. A single
    /// slow turn is noise; three of the last four is a pattern.
    static let sampleWindow = 4
    static let slowSamplesToDemote = 3

    // MARK: - Session

    /// Opens a new session when the gap since the last recorded attempt exceeds the
    /// timeout, clearing health. Returns whether a new session was opened.
    mutating func openSessionIfIdle(at now: Date) -> Bool {
        guard let lastActivity else {
            lastActivity = now
            return false
        }
        guard now.timeIntervalSince(lastActivity) > sessionIdleSeconds else { return false }
        entries.removeAll()
        self.lastActivity = now
        return true
    }

    private var sessionIdleSeconds: TimeInterval {
        Double(Self.sessionIdleTimeout.components.seconds)
    }

    mutating func markActivity(now: Date) {
        lastActivity = now
    }

    // MARK: - Reads

    func isHealthy(_ model: String, now: Date) -> Bool {
        guard let entry = entries[model] else { return true }
        if entry.retiredForSession { return false }
        guard let until = entry.quarantinedUntil else { return true }
        return now >= until
    }

    func slowFirstTokenSamples(_ model: String) -> Int {
        entries[model]?.recentSamples.count(where: \.wasSlowFirstToken) ?? 0
    }

    func isRetired(_ model: String) -> Bool {
        entries[model]?.retiredForSession ?? false
    }

    func quarantineReason(_ model: String) -> String? {
        guard let entry = entries[model] else { return nil }
        if entry.retiredForSession { return "retired" }
        guard entry.quarantinedUntil != nil else { return nil }
        return "unhealthy x\(entry.consecutiveQuarantines)"
    }

    // MARK: - Writes

    mutating func markRetired(_ model: String, now: Date) {
        var entry = entries[model] ?? Entry()
        entry.retiredForSession = true
        entries[model] = entry
        lastActivity = now
    }

    /// Quarantines a model with backoff. Returns the expiry, for logging.
    @discardableResult
    mutating func quarantine(_ model: String, now: Date, base: Duration) -> Date {
        var entry = entries[model] ?? Entry()
        entry.consecutiveQuarantines += 1
        let multiplier = pow(2.0, Double(entry.consecutiveQuarantines - 1))
        let seconds = min(
            Double(base.components.seconds) * multiplier,
            Double(Self.maxQuarantine.components.seconds)
        )
        let until = now.addingTimeInterval(seconds)
        entry.quarantinedUntil = until
        // A quarantined model's samples say nothing useful once it comes back.
        entry.recentSamples.removeAll()
        entries[model] = entry
        lastActivity = now
        return until
    }

    /// Records a completed attempt. Returns a reason when the model has now been slow
    /// often enough to step aside.
    mutating func recordSample(
        _ model: String,
        wasSlowFirstToken: Bool,
        wasSlowThroughput: Bool,
        now: Date
    ) -> DegradationReason? {
        var entry = entries[model] ?? Entry()
        entry.recentSamples.append(
            Sample(wasSlowFirstToken: wasSlowFirstToken, wasSlowThroughput: wasSlowThroughput)
        )
        if entry.recentSamples.count > Self.sampleWindow {
            entry.recentSamples.removeFirst(entry.recentSamples.count - Self.sampleWindow)
        }
        entries[model] = entry
        lastActivity = now

        let slowFirstToken = entry.recentSamples.count(where: \.wasSlowFirstToken)
        let slowThroughput = entry.recentSamples.count(where: \.wasSlowThroughput)
        if slowFirstToken >= Self.slowSamplesToDemote { return .slowFirstToken }
        if slowThroughput >= Self.slowSamplesToDemote { return .slowThroughput }
        return nil
    }

    /// Resets the backoff after a healthy run, so an old bad patch doesn't make the next
    /// quarantine disproportionately long. Slowness history ages out via the sample
    /// window instead.
    mutating func recordSuccess(_ model: String, now: Date) {
        guard var entry = entries[model] else {
            lastActivity = now
            return
        }
        entry.consecutiveQuarantines = 0
        entries[model] = entry
        lastActivity = now
    }
}
