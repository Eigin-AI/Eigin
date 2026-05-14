import SwiftUI

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
