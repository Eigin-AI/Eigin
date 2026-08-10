import SwiftUI

/// Manages the currently selected theme and persists the user's choice to `UserDefaults`.
/// Inject via `@Environment(\.themeManager)`.
@Observable
final class ThemeManager: @unchecked Sendable {
    static let availableThemes: [any Theme] = [
        DefaultTheme(),
        SystemTheme(),
    ]

    var currentTheme: any Theme

    init() {
        let savedID = UserDefaults.standard
            .string(forKey: StorageKey.selectedTheme) ?? DefaultTheme().id
        currentTheme = Self.availableThemes.first { $0.id == savedID } ?? DefaultTheme()
    }

    func selectTheme(_ theme: any Theme) {
        currentTheme = theme
        UserDefaults.standard.set(theme.id, forKey: StorageKey.selectedTheme)
    }

    func colors(for colorScheme: ColorScheme) -> ResolvedColors {
        currentTheme.colors(for: colorScheme)
    }
}

extension EnvironmentValues {
    @Entry var themeManager: ThemeManager = .init()
}

// MARK: - Theme Resolver

private struct ThemeResolver: ViewModifier {
    @Environment(\.themeManager) private var themeManager
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let colors = themeManager.colors(for: colorScheme)
        // Built here, not per view body: resolving its fonts is costly and it only
        // changes with the theme.
        return content
            .environment(\.colors, colors)
            .environment(\.markdownRenderConfig, .eigin(colors: colors))
    }
}

extension View {
    func resolveTheme() -> some View {
        modifier(ThemeResolver())
    }
}
