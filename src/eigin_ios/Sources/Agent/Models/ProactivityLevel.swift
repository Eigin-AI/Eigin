import Foundation

/// Controls whether and how aggressively the agent runs background reviews.
enum ProactivityLevel: Int, Codable, CaseIterable {
    case reactive = 0
    case balanced = 1
    case proactive = 2

    var displayName: String {
        switch self {
        case .reactive: Localized.Ui.reactive
        case .balanced: Localized.Settings.balanced
        case .proactive: Localized.Ui.proactive
        }
    }

    var description: String {
        switch self {
        case .reactive: Localized.Settings.Proactivity.Reactive.short
        case .balanced: Localized.Settings.Proactivity.Balanced.short
        case .proactive: Localized.Settings.Proactivity.Proactive.short
        }
    }

    var systemImage: String {
        switch self {
        case .reactive: "moon.zzz"
        case .balanced: "arrow.left.arrow.right"
        case .proactive: "bolt"
        }
    }

    var isBackgroundEnabled: Bool {
        self != .reactive
    }

    var allowsWriteTools: Bool {
        self == .proactive
    }

    /// Minimum interval between background runs.
    var schedulingInterval: TimeInterval? {
        switch self {
        case .reactive: nil
        case .balanced: 12 * 3600 // Every 12 hours
        case .proactive: 6 * 3600 // Ever 6 hours
        }
    }
}
