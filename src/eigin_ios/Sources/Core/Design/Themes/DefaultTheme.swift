import SwiftUI

/// A purple-accented theme with custom light and dark palettes.
struct DefaultTheme: Theme {
    var name: String {
        Localized.Ui.defaultLabel
    }

    let id = "default"

    func colors(for colorScheme: ColorScheme) -> ResolvedColors {
        switch colorScheme {
        case .light:
            return ResolvedColors(
                background: Color(red: 0.97, green: 0.96, blue: 0.98),
                surface: .white,
                surfaceSecondary: Color(red: 0.94, green: 0.92, blue: 0.96),
                textPrimary: Color(red: 0.10, green: 0.10, blue: 0.12),
                textSecondary: Color(red: 0.40, green: 0.38, blue: 0.44),
                textTertiary: Color(red: 0.60, green: 0.58, blue: 0.64),
                accent: Color(red: 0.60, green: 0.30, blue: 0.88),
                accentSecondary: Color(red: 0.01, green: 0.55, blue: 0.14),
                border: Color(red: 0.84, green: 0.82, blue: 0.87),
                destructive: Color(red: 0.80, green: 0.25, blue: 0.20)
            )
        case .dark:
            return ResolvedColors(
                background: Color(red: 0.086, green: 0.086, blue: 0.094),
                surface: Color(red: 0.122, green: 0.122, blue: 0.133),
                surfaceSecondary: Color(red: 0.165, green: 0.165, blue: 0.184),
                textPrimary: .white,
                textSecondary: Color(red: 0.69, green: 0.69, blue: 0.71),
                textTertiary: Color(red: 0.50, green: 0.50, blue: 0.53),
                accent: Color(red: 0.77, green: 0.40, blue: 1.0),
                accentSecondary: Color(red: 0.01, green: 0.66, blue: 0.17),
                border: Color(red: 0.25, green: 0.25, blue: 0.28),
                destructive: Color(red: 1.0, green: 0.47, blue: 0.27)
            )
        @unknown default:
            return colors(for: .dark)
        }
    }
}
