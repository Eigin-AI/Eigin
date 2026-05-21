import Foundation

enum FeedbackType: String, CaseIterable, Identifiable {
    case bug
    case feature
    case general

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .bug: Localized.Settings.Feedback.Kind.bug
        case .feature: Localized.Settings.Feedback.Kind.feature
        case .general: Localized.Settings.Feedback.Kind.general
        }
    }
}
