import SwiftUI

/// A theme that defers to the standard iOS system colors and semantic tokens.
struct SystemTheme: Theme {
    var name: String {
        Localized.ToolCategory.system
    }

    let id = "system"

    func colors(for colorScheme: ColorScheme) -> ResolvedColors {
        switch colorScheme {
        case .light:
            return ResolvedColors(
                background: Color(.systemGroupedBackground),
                surface: Color(.secondarySystemGroupedBackground),
                surfaceSecondary: Color(.tertiarySystemGroupedBackground),
                textPrimary: Color(.label),
                textSecondary: Color(.secondaryLabel),
                textTertiary: Color(.tertiaryLabel),
                accent: .blue,
                accentSecondary: .indigo,
                border: Color(.separator),
                destructive: .red
            )
        case .dark:
            return ResolvedColors(
                background: Color(.systemGroupedBackground),
                surface: Color(.secondarySystemGroupedBackground),
                surfaceSecondary: Color(.tertiarySystemGroupedBackground),
                textPrimary: Color(.label),
                textSecondary: Color(.secondaryLabel),
                textTertiary: Color(.tertiaryLabel),
                accent: .blue,
                accentSecondary: .indigo,
                border: Color(.separator),
                destructive: .red
            )
        @unknown default:
            return colors(for: .light)
        }
    }
}
