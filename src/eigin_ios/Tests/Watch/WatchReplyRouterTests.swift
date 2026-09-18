@testable import Eigin
import Testing

@Suite("WatchReplyRouter")
struct WatchReplyRouterTests {
    @Test("A live send hands the announcement to the watch")
    func liveSendAnnouncesFromWatch() {
        #expect(WatchReplyRouter.announcer(for: .live) == .watch)
    }

    @Test("A queued transfer leaves the announcement to the phone")
    func queuedTransferAnnouncesFromPhone() {
        #expect(WatchReplyRouter.announcer(for: .queued) == .phone)
    }
}
