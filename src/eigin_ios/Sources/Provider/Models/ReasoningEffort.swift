import Foundation

/// Shared wire labels; each model and endpoint supports its own subset.
enum ReasoningEffort: String, Codable, Sendable, CaseIterable {
    case none, minimal, low, medium, high, xhigh, max
}

/// Verified effort settings for Auto routing and request serialization.
struct ReasoningControl: Sendable {
    let supportedEfforts: Set<ReasoningEffort>
    let fastEffort: ReasoningEffort
    let escalatedEffort: ReasoningEffort
    let defaultEffort: ReasoningEffort?

    init(
        supportedEfforts: Set<ReasoningEffort>,
        fastEffort: ReasoningEffort,
        escalatedEffort: ReasoningEffort,
        defaultEffort: ReasoningEffort? = nil
    ) {
        precondition(supportedEfforts.contains(fastEffort) && supportedEfforts
            .contains(escalatedEffort))
        precondition(defaultEffort.map { supportedEfforts.contains($0) } ?? true)
        self.supportedEfforts = supportedEfforts
        self.fastEffort = fastEffort
        self.escalatedEffort = escalatedEffort
        self.defaultEffort = defaultEffort
    }

    /// Applies the configured default and caps requests at the escalated setting.
    func requestEffort(_ requested: ReasoningEffort?) -> ReasoningEffort? {
        guard let effort = requested ?? defaultEffort else { return nil }
        guard supportedEfforts.contains(effort) else { return escalatedEffort }
        let order = ReasoningEffort.allCases
        guard let requestedIndex = order.firstIndex(of: effort),
              let maximumIndex = order.firstIndex(of: escalatedEffort)
        else { return escalatedEffort }
        return requestedIndex > maximumIndex ? escalatedEffort : effort
    }
}
