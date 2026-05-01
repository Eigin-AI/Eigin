import SwiftUI

/// App-wide typography, providing consistent font styles across all views.
enum Typography {
    static let largeTitle: Font = .system(.largeTitle, design: .default, weight: .bold)
    static let title: Font = .system(.title2, design: .default, weight: .semibold)
    static let headline: Font = .system(.headline, design: .default, weight: .semibold)
    static let body: Font = .system(.body, design: .default, weight: .regular)
    static let callout: Font = .system(.callout, design: .default, weight: .regular)
    static let caption: Font = .system(.caption, design: .default, weight: .regular)
    static let mono: Font = .system(.body, design: .monospaced, weight: .regular)
}
