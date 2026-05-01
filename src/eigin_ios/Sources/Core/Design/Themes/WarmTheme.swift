import SwiftUI

/// An earthy, warm-toned theme with brown and amber accents.
struct WarmTheme: Theme {
    var name: String {
        Localized.Ui.warm
    }

    let id = "warm"

    func colors(for colorScheme: ColorScheme) -> ResolvedColors {
        switch colorScheme {
        case .light:
            return ResolvedColors(
                background: Color(red: 0.96, green: 0.94, blue: 0.90),
                surface: Color(red: 0.99, green: 0.97, blue: 0.94),
                surfaceSecondary: Color(red: 0.93, green: 0.90, blue: 0.86),
                textPrimary: Color(red: 0.18, green: 0.14, blue: 0.10),
                textSecondary: Color(red: 0.44, green: 0.38, blue: 0.32),
                textTertiary: Color(red: 0.60, green: 0.55, blue: 0.48),
                accent: Color(red: 0.52, green: 0.34, blue: 0.18),
                accentSecondary: Color(red: 0.62, green: 0.44, blue: 0.24),
                border: Color(red: 0.84, green: 0.78, blue: 0.70),
                destructive: Color(red: 0.72, green: 0.24, blue: 0.18)
            )
        case .dark:
            return ResolvedColors(
                background: Color(red: 0.09, green: 0.08, blue: 0.06),
                surface: Color(red: 0.15, green: 0.13, blue: 0.10),
                surfaceSecondary: Color(red: 0.21, green: 0.18, blue: 0.14),
                textPrimary: Color(red: 0.94, green: 0.90, blue: 0.84),
                textSecondary: Color(red: 0.68, green: 0.62, blue: 0.54),
                textTertiary: Color(red: 0.50, green: 0.46, blue: 0.40),
                accent: Color(red: 0.76, green: 0.54, blue: 0.30),
                accentSecondary: Color(red: 0.62, green: 0.44, blue: 0.24),
                border: Color(red: 0.28, green: 0.24, blue: 0.20),
                destructive: Color(red: 0.82, green: 0.30, blue: 0.24)
            )
        @unknown default:
            return colors(for: .light)
        }
    }
}
