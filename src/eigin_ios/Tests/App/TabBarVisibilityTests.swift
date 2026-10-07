@testable import Eigin
import Testing

/// Verifies the tab-bar visibility toggle that `ContentView` drives from
/// the `HidesTabBarPreferenceKey` preference: hidden while any publisher is
/// present, visible again once none are.
@MainActor
@Suite("TabBarVisibility")
struct TabBarVisibilityTests {
    private func make() -> TabBarVisibility {
        TabBarVisibility()
    }

    @Test func setHiddenHidesAndShows() {
        let bar = make()
        #expect(bar.isVisible)

        bar.setHidden(true)
        #expect(!bar.isVisible)

        bar.setHidden(false)
        #expect(bar.isVisible)
    }

    @Test func repeatedSameStateIsANoOp() {
        let bar = make()

        bar.setHidden(true)
        bar.setHidden(true)
        #expect(!bar.isVisible)

        bar.setHidden(false)
        bar.setHidden(false)
        #expect(bar.isVisible)
    }
}
