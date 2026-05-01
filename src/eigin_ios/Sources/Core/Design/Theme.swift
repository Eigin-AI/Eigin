import SwiftUI

/// The concrete color values for a theme after resolving for the current color scheme (light or
/// dark).
struct ResolvedColors {
    let background: Color
    let surface: Color
    let surfaceSecondary: Color
    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color
    let accent: Color
    let accentSecondary: Color
    let border: Color
    let destructive: Color
}

/// Defines a visual theme that provides a full color palette for both light and dark appearances.
/// Conform to this protocol to add a new selectable theme.
protocol Theme: Sendable {
    var name: String { get }
    var id: String { get }
    func colors(for colorScheme: ColorScheme) -> ResolvedColors
}

extension EnvironmentValues {
    @Entry var colors: ResolvedColors = DefaultTheme().colors(for: .light)
}
