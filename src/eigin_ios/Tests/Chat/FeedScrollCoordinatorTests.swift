@testable import Eigin
import Testing

@MainActor
@Suite("FeedScrollCoordinator")
struct FeedScrollCoordinatorTests {
    private func userItem(_ id: String) -> ChatItem {
        .message(id: id, role: "user", content: "hello")
    }

    private func assistantItem(_ id: String) -> ChatItem {
        .message(id: id, role: "assistant", content: "hi")
    }

    @Test("A declared send pins the trailing user message")
    func sendPinsTrailingUser() {
        let coordinator = FeedScrollCoordinator()
        coordinator.declareSending()

        let outcome = coordinator.scrollBehaviorForNewItems([assistantItem("a0"), userItem("u1")])

        #expect(outcome == .pinToTop("u1"))
        #expect(coordinator.pinnedUserMessageID == "u1")
    }

    @Test("A pagination append (no send declared) does not pin")
    func paginationDoesNotPin() {
        let coordinator = FeedScrollCoordinator()
        // No declareSending(): a windowed batch that happens to end on a user message.
        let outcome = coordinator.scrollBehaviorForNewItems([assistantItem("a0"), userItem("u1")])

        #expect(outcome == .none)
        #expect(coordinator.pinnedUserMessageID == nil)
    }

    @Test("A load-newer append anchors to the previous last item")
    func loadNewerAnchors() {
        let coordinator = FeedScrollCoordinator()
        coordinator.beginLoadNewer(lastItemID: "a0")

        let outcome = coordinator.scrollBehaviorForNewItems([assistantItem("a0"), userItem("u1")])

        #expect(outcome == .anchorToBottom("a0"))
        #expect(coordinator.pinnedUserMessageID == nil)
    }

    @Test("Anchoring wins over a stale send intent")
    func anchorBeatsSend() {
        let coordinator = FeedScrollCoordinator()
        coordinator.declareSending()
        coordinator.beginLoadNewer(lastItemID: "a0")

        let outcome = coordinator.scrollBehaviorForNewItems([assistantItem("a0"), userItem("u1")])

        #expect(outcome == .anchorToBottom("a0"))
    }

    @Test("The same user message is not re-pinned on a repeat append")
    func noRepin() {
        let coordinator = FeedScrollCoordinator()
        coordinator.declareSending()
        _ = coordinator.scrollBehaviorForNewItems([userItem("u1")])

        coordinator.declareSending()
        let outcome = coordinator.scrollBehaviorForNewItems([userItem("u1")])

        #expect(outcome == .none)
        #expect(coordinator.pinnedUserMessageID == "u1")
    }

    @Test("An assistant trailing item never pins")
    func assistantTailNeverPins() {
        let coordinator = FeedScrollCoordinator()
        coordinator.declareSending()

        let outcome = coordinator.scrollBehaviorForNewItems([userItem("u0"), assistantItem("a1")])

        #expect(outcome == .none)
    }

    @Test("Grow-in marks only items that appeared after the turn started")
    func liveRowTracking() {
        let coordinator = FeedScrollCoordinator()
        let existing = [userItem("u0"), assistantItem("a0")]
        coordinator.phaseChanged(to: .waiting, items: existing)

        #expect(coordinator.isLiveRow("a0", phase: .streaming) == false)
        #expect(coordinator.isLiveRow("a1", phase: .streaming) == true) // new mid-turn
        #expect(coordinator.isLiveRow("a1", phase: .idle) == false) // not while idle
    }

    @Test("Idle phase clears grow-in tracking")
    func idleClearsTracking() {
        let coordinator = FeedScrollCoordinator()
        coordinator.phaseChanged(to: .waiting, items: [userItem("u0")])
        coordinator.phaseChanged(to: .idle, items: [userItem("u0")])

        #expect(coordinator.preStreamItemIDs.isEmpty)
    }
}
