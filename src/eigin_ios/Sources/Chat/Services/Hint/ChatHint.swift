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

        // Filter catalog: condition must pass and cooldown must have elapsed
        let eligible = HintCatalog.all.filter { hint in
            guard hint.condition(context) else { return false }
            if let lastDelivered = history.lastDelivery(for: hint.id) {
                return now.timeIntervalSince(lastDelivered) >= hint.cooldown
            }
            return true
        }

        // Pick highest priority (highest number wins)
        guard let best = eligible.max(by: { $0.priority < $1.priority }) else { return nil }

        // Record delivery and return the text
        history.recordDelivery(for: best.id, at: now)
        return best.template(context)
    }
}

// MARK: - Hint History

/// Tracks when each hint type was last delivered, per agent. Stored in UserDefaults.
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

    func recordDelivery(for hintID: String, at date: Date = Date()) {
        var dict = UserDefaults.standard.dictionary(forKey: key) as? [String: Double] ?? [:]
        dict[hintID] = date.timeIntervalSinceReferenceDate
        UserDefaults.standard.set(dict, forKey: key)
    }
}
