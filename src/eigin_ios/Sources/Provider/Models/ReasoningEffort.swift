import EiginSDK
import Foundation

/// Shared wire labels; each model and endpoint supports its own subset.
enum ReasoningEffort: String, Codable, Sendable, CaseIterable {
    case none, minimal, low, medium, high, xhigh, max
}

/// App-facing values supplied by the SDK's verified effort policy.
struct ReasoningControl: Sendable {
    let supportedEfforts: Set<ReasoningEffort>
    let fastEffort: ReasoningEffort
    let escalatedEffort: ReasoningEffort
    let defaultEffort: ReasoningEffort?

    init(_ value: EiginSDK.ModelCatalog.ReasoningControl) {
        supportedEfforts = Set(value.supportedEfforts.map(ReasoningEffort.init))
        fastEffort = ReasoningEffort(value.fastEffort)
        escalatedEffort = ReasoningEffort(value.escalatedEffort)
        defaultEffort = value.defaultEffort.map(ReasoningEffort.init)
    }
}

extension ReasoningEffort {
    var sdk: EiginSDK.ModelCatalog.Effort {
        switch self {
        case .none: .none
        case .minimal: .minimal
        case .low: .low
        case .medium: .medium
        case .high: .high
        case .xhigh: .xhigh
        case .max: .max
        }
    }

    init(_ effort: EiginSDK.ModelCatalog.Effort) {
        switch effort {
        case .none: self = .none
        case .minimal: self = .minimal
        case .low: self = .low
        case .medium: self = .medium
        case .high: self = .high
        case .xhigh: self = .xhigh
        case .max: self = .max
        }
    }
}
