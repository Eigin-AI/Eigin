import Factory
import Observation
import SwiftUI

/// Tracks how many nested views across the app have requested the tab bar be hidden.
/// The bar is visible when depth is zero, hidden otherwise.
///
/// Read through Factory injection (`@Injected(\.tabBarVisibility)`);
/// `.shared` is the
/// production instance. Usage from destination views:
///
///     .onAppear  { tabBarVisibility.push() }
///     .onDisappear { tabBarVisibility.pop() }
///
/// Or use the shorthand modifier:
///     .hidesTabBar()
@MainActor
@Observable
final class TabBarVisibility {
    static let shared = TabBarVisibility()

    private(set) var isVisible: Bool = true

    /// Clamping happens in the mutators, not didSet: under @Observable an
    /// assignment inside didSet re-enters the generated setter and recurses.
    private var depth: Int = 0 {
        didSet {
            let new = depth <= 0
            if new != isVisible {
                withAnimation(Animations.snap) {
                    isVisible = new
                }
            }
        }
    }

    /// Internal so tests can build isolated instances; the container hands
    /// out `.shared` unless overridden.
    init() {}

    func push() {
        depth += 1
    }

    func pop() {
        depth = max(0, depth - 1)
    }

    func popAll() {
        depth = 0
    }
}

// MARK: - View modifier

extension View {
    /// Hides the bottom tab bar while this view is on-screen.
    func hidesTabBar() -> some View {
        modifier(HidesTabBarModifier())
    }

    /// Adds permanent bottom padding equal to the tab bar height so scroll
    /// content clears the bar area even when the bar is hidden.
    func tabBarPadding() -> some View {
        safeAreaInset(edge: .bottom) {
            Spacer().frame(height: AppNavigationBar.height)
        }
    }
}

private struct HidesTabBarModifier: ViewModifier {
    @Injected(\.tabBarVisibility) private var tabBarVisibility

    func body(content: Content) -> some View {
        content
            .onAppear { tabBarVisibility.push() }
            .onDisappear { tabBarVisibility.pop() }
    }
}
