import Foundation

/// Shared wire labels; each model and endpoint supports its own subset.
enum ReasoningEffort: String, Codable, Sendable, CaseIterable {
    case none, minimal, low, medium, high, xhigh, max
}

/// Verified effort controls and the two settings used by Auto routing.
struct ReasoningControl: Sendable {
    let supportedEfforts: Set<ReasoningEffort>
    let fastEffort: ReasoningEffort
    let escalatedEffort: ReasoningEffort

    init(
        supportedEfforts: Set<ReasoningEffort>,
        fastEffort: ReasoningEffort,
        escalatedEffort: ReasoningEffort
    ) {
        precondition(supportedEfforts.contains(fastEffort) && supportedEfforts
            .contains(escalatedEffort))
        self.supportedEfforts = supportedEfforts
        self.fastEffort = fastEffort
        self.escalatedEffort = escalatedEffort
    }
}
