@testable import Eigin
import Testing
import UIKit

@Suite("WatchLink")
struct WatchLinkTests {
    @Test("a foreground-active app keeps its banner to itself")
    func foregroundSkipsNotification() {
        #expect(!WatchLink.shouldNotify(appState: .active))
    }

    @Test("background and inactive still announce")
    func backgroundAnnounces() {
        #expect(WatchLink.shouldNotify(appState: .background))
        #expect(WatchLink.shouldNotify(appState: .inactive))
    }
}
