import Combine
import SwiftUI

/// Tracks how many nested views across the app have requested the tab bar be hidden.
/// The bar is visible when depth is zero, hidden otherwise.
///
/// Usage from destination views:
///     .onAppear  { TabBarVisibility.shared.push() }
///     .onDisappear { TabBarVisibility.shared.pop() }
///
/// Or use the shorthand modifier:
///     .hidesTabBar()
@MainActor
final class TabBarVisibility: ObservableObject {
    static let shared = TabBarVisibility()

    @Published private(set) var isVisible: Bool = true

    private var depth: Int = 0 {
        didSet {
            let new = depth <= 0
            if new != isVisible {
                withAnimation(Animations.snap) {
                    isVisible = new
                }
            }
            depth = max(0, depth)
        }
    }

    private init() {}

    func push() {
        depth += 1
    }

    func pop() {
        depth -= 1
    }

    func popAll() {
        depth = 0
    }
}

// MARK: - View modifier

extension View {
    /// Hides the bottom tab bar while this view is on-screen.
    func hidesTabBar() -> some View {
        onAppear { TabBarVisibility.shared.push() }
            .onDisappear { TabBarVisibility.shared.pop() }
    }

    /// Adds permanent bottom padding equal to the tab bar height so scroll
    /// content clears the bar area even when the bar is hidden.
    func tabBarPadding() -> some View {
        safeAreaInset(edge: .bottom) {
            Spacer().frame(height: AppNavigationBar.height)
        }
    }
}
