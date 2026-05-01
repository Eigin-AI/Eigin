import SwiftUI

/// Manages the currently selected theme and persists the user's choice to `UserDefaults`.
/// Inject via `@Environment(\.themeManager)`.
@Observable
final class ThemeManager: @unchecked Sendable {
    static let availableThemes: [any Theme] = [
        DefaultTheme(),
        WarmTheme(),
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
        content
            .environment(\.colors, themeManager.colors(for: colorScheme))
    }
}

extension View {
    func resolveTheme() -> some View {
        modifier(ThemeResolver())
    }
}
