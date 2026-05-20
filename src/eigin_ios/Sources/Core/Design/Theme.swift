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
    @Entry var gridBreakpoint: Grid.Breakpoint = Grid.mobile
}

/// Maps the current horizontal size class to a layout grid breakpoint.
private struct GridBreakpointResolver: ViewModifier {
    @Environment(\.horizontalSizeClass) private var sizeClass

    func body(content: Content) -> some View {
        content
            .environment(
                \.gridBreakpoint,
                sizeClass == .regular ? Grid.tablet : Grid.mobile
            )
    }
}

extension View {
    /// Injects the current grid breakpoint into the environment based on the
    /// device's horizontal size class. Call at the root of a design-component
    /// preview or anywhere a sub-view needs responsive sizing.
    func resolveGridBreakpoint() -> some View {
        modifier(GridBreakpointResolver())
    }
}
