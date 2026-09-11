@testable import Eigin
import Testing

/// Verifies the tab-bar visibility depth bookkeeping: hidden while any view
/// pushes, visible again once the stack drains, clamped at zero.
@MainActor
@Suite("TabBarVisibility")
struct TabBarVisibilityTests {
    private func make() -> TabBarVisibility {
        TabBarVisibility()
    }

    @Test func pushHidesAndPopShows() {
        let bar = make()
        #expect(bar.isVisible)

        bar.push()
        #expect(!bar.isVisible)

        bar.pop()
        #expect(bar.isVisible)
    }

    @Test func nestedPushesKeepBarHiddenUntilStackDrains() {
        let bar = make()
        bar.push()
        bar.push()
        bar.pop()
        #expect(!bar.isVisible)

        bar.pop()
        #expect(bar.isVisible)
    }

    @Test func popBelowZeroClampsInsteadOfDesyncing() {
        let bar = make()
        bar.pop()
        bar.pop()

        bar.push()
        #expect(!bar.isVisible)

        bar.pop()
        #expect(bar.isVisible)
    }

    @Test func popAllDrainsImmediately() {
        let bar = make()
        bar.push()
        bar.push()
        bar.popAll()
        #expect(bar.isVisible)
    }
}
