import Foundation

/// Evaluates and delivers hints (gentle suggestions) in chat sessions.
enum ChatHint {
    // MARK: - Evaluation

    /// Evaluates the hint catalog and returns plain-text hint content if a hint
    /// should fire this turn. Returns `nil` if no hint is relevant or all are
    /// on cooldown.
    ///
    /// The returned text is plain markdown — the caller (usually a
    /// ``ChatHintSource``) embeds it in the ephemeral ``Gatekeeper`` block.
    static func evaluate(
        agentID: UUID,
        bootstrapComplete: Bool,
        messages: [ChatMessage],
        hasSpaces: Bool,
        needsCompaction: Bool,
        initiative: ProactivityLevel
    ) -> String? {
        // Never hint during bootstrap or on the first exchange
        guard bootstrapComplete else { return nil }
        guard messages.contains(where: { $0.role == "assistant" }) else { return nil }

        let context = HintContext(
            messages: messages,
            hasSpaces: hasSpaces,
            needsCompaction: needsCompaction,
            initiative: initiative
        )

        let history = HintHistory(agentID: agentID)
        let now = Date()

        // Filter catalog: condition must pass, and the hint must be eligible —
        // within its current burst or past its cooldown.
        let eligible = HintCatalog.all.filter { hint in
            guard hint.condition(context) else { return false }
            return history.isEligible(
                hint.id,
                cooldown: hint.cooldown,
                burst: hint.burst,
                now: now
            )
        }

        // Pick highest priority (highest number wins)
        guard let best = eligible.max(by: { $0.priority < $1.priority }) else { return nil }

        // Record delivery (starting a new burst if the cooldown has elapsed)
        history.recordDelivery(for: best.id, cooldown: best.cooldown, at: now)
        return best.template(context).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Hint History

/// Tracks how often each hint type was delivered, per agent. Stored in
/// UserDefaults.
final class HintHistory: Sendable {
    private let key: String

    init(agentID: UUID) {
        key = "hint_history_\(agentID.uuidString)"
    }

    func lastDelivery(for hintID: String) -> Date? {
        let dict = UserDefaults.standard.dictionary(forKey: key) as? [String: Double] ?? [:]
        guard let interval = dict[hintID] else { return nil }
        return Date(timeIntervalSinceReferenceDate: interval)
    }

    /// Whether the hint may fire: never delivered, still within its current
    /// burst, or past its cooldown (which starts a new burst).
    func isEligible(_ hintID: String, cooldown: TimeInterval, burst: Int, now: Date) -> Bool {
        guard let last = lastDelivery(for: hintID) else { return true }
        if now.timeIntervalSince(last) >= cooldown { return true }
        return showCount(for: hintID) < burst
    }

    /// Records a delivery. Counts consecutive shows within one burst; a burst
    /// restarts (count resets to 1) once the cooldown has elapsed.
    func recordDelivery(for hintID: String, cooldown: TimeInterval, at date: Date = Date()) {
        var dict = UserDefaults.standard.dictionary(forKey: key) as? [String: Double] ?? [:]
        var shows = UserDefaults.standard.dictionary(forKey: showsKey) as? [String: Int] ?? [:]

        let withinBurst = lastDelivery(for: hintID)
            .map { date.timeIntervalSince($0) < cooldown } ?? false
        shows[hintID] = withinBurst ? (shows[hintID] ?? 0) + 1 : 1
        dict[hintID] = date.timeIntervalSinceReferenceDate

        UserDefaults.standard.set(dict, forKey: key)
        UserDefaults.standard.set(shows, forKey: showsKey)
    }

    private func showCount(for hintID: String) -> Int {
        let shows = UserDefaults.standard.dictionary(forKey: showsKey) as? [String: Int] ?? [:]
        return shows[hintID] ?? 0
    }

    private var showsKey: String {
        "hint_shows_" + key
    }
}
