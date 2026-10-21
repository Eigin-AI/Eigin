import Factory
import Observation
import SwiftUI

/// Controls whether the bottom tab bar is visible. `ContentView` drives it
/// from the `HidesTabBarPreferenceKey` preference.
@MainActor
@Observable
final class TabBarVisibility {
    static let shared = TabBarVisibility()

    private(set) var isVisible: Bool = true

    /// Internal so tests can build isolated instances; the container hands
    /// out `.shared` unless overridden.
    init() {}

    func setHidden(_ hidden: Bool) {
        let visible = !hidden
        guard visible != isVisible else { return }
        if visible {
            // Returning: fade back in, unhurried.
            withAnimation(.easeOut(duration: Animations.slow)) {
                isVisible = visible
            }
        } else {
            // Hiding: remove instantly rather than animating out. The
            // navigation transition does not run root-level animations
            // concurrently, so a slide would linger over the incoming
            // screen's bottom content (e.g. the chat input bar).
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                isVisible = visible
            }
        }
    }
}

// MARK: - Preference plumbing

/// Preference set by any view that wants the tab bar hidden.
struct HidesTabBarPreferenceKey: PreferenceKey {
    static let defaultValue = false

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

// MARK: - View modifier

extension View {
    /// Hides the bottom tab bar while this view is on-screen.
    func hidesTabBar() -> some View {
        preference(key: HidesTabBarPreferenceKey.self, value: true)
    }

    /// Adds permanent bottom padding equal to the tab bar height so scroll
    /// content clears the bar area even when the bar is hidden.
    func tabBarPadding() -> some View {
        safeAreaInset(edge: .bottom) {
            Spacer().frame(height: AppNavigationBar.height)
        }
    }
}
