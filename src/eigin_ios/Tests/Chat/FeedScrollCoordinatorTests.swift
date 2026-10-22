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

    @Test(
        "Incoming replies leave navigation alone at and away from the bottom",
        arguments: [true, false]
    )
    func incomingReplyDoesNotNavigate(atBottom: Bool) {
        let coordinator = FeedScrollCoordinator()
        coordinator.scrollPositionChanged(atBottom)

        let outcome = coordinator.scrollBehaviorForNewItems([userItem("u1"), assistantItem("a1")])

        #expect(outcome == .none)
        #expect(coordinator.isAtBottom == atBottom)
    }

    @Test("Streaming and completion preserve the send pin")
    func streamingPreservesPin() {
        let coordinator = FeedScrollCoordinator()
        coordinator.declareSending()
        _ = coordinator.scrollBehaviorForNewItems([userItem("u1")])
        let items = [userItem("u1"), assistantItem("a1")]

        for phase: StreamThrottler.Phase in [.waiting, .streaming, .done, .idle] {
            coordinator.phaseChanged(to: phase, items: items)
            #expect(coordinator.pinnedUserMessageID == "u1")
            #expect(coordinator.scrollBehaviorForNewItems(items) == .none)
        }
    }

    // MARK: - Reveal

    @Test("A normal conversation's first reveal rests at the bottom")
    func revealRestsAtBottomOnce() {
        let coordinator = FeedScrollCoordinator()

        #expect(coordinator.shouldRevealAtBottom(isAgentOpened: false))
        #expect(!coordinator.shouldRevealAtBottom(isAgentOpened: false))
    }

    @Test("An agent-opened conversation skips the bottom reveal and consumes the one shot")
    func agentOpenSkipsBottomReveal() {
        let coordinator = FeedScrollCoordinator()

        #expect(!coordinator.shouldRevealAtBottom(isAgentOpened: true))
        #expect(!coordinator.shouldRevealAtBottom(isAgentOpened: false))
    }

    @Test("An active pin outranks the bottom reveal")
    func pinnedOutranksBottomReveal() {
        let coordinator = FeedScrollCoordinator()
        coordinator.declareSending()
        _ = coordinator.scrollBehaviorForNewItems([userItem("u1")])

        #expect(coordinator.pinnedUserMessageID == "u1")
        #expect(!coordinator.shouldRevealAtBottom(isAgentOpened: false))
    }

    // MARK: - Initial anchor

    @Test("A normal conversation initially opens at the bottom")
    func initialAnchorBottom() {
        let coordinator = FeedScrollCoordinator()

        #expect(coordinator.initialAnchor(isAgentOpened: false) == .bottom)
    }

    @Test("An agent-initiated opening anchors to the top")
    func initialAnchorTopForAgentOpen() {
        let coordinator = FeedScrollCoordinator()

        // Opens with a summary that's longer than one viewport — top anchor
        // shows it from the top instead of bottom-anchoring past it.
        #expect(coordinator.initialAnchor(isAgentOpened: true) == .top)
    }

    @Test("A pinned turn drops the initial anchor so it can't tug the pin")
    func initialAnchorNilWhilePinned() {
        let coordinator = FeedScrollCoordinator()
        coordinator.declareSending()
        _ = coordinator.scrollBehaviorForNewItems([userItem("u1")])

        #expect(coordinator.pinnedUserMessageID == "u1")
        #expect(coordinator.initialAnchor(isAgentOpened: false) == nil)
    }

    @Test("A pending pagination batch drops the initial anchor")
    func initialAnchorNilWhilePaginating() {
        let coordinator = FeedScrollCoordinator()
        coordinator.beginLoadNewer(lastItemID: "a0")

        #expect(coordinator.initialAnchor(isAgentOpened: false) == nil)
    }

    @Test("A pin wins over an agent-opened flag")
    func pinBeatsAgentOpen() {
        let coordinator = FeedScrollCoordinator()
        coordinator.declareSending()
        _ = coordinator.scrollBehaviorForNewItems([userItem("u1")])

        #expect(coordinator.initialAnchor(isAgentOpened: true) == nil)
    }

    @Test("A pending pagination batch wins over an agent-opened flag")
    func paginationBeatsAgentOpen() {
        let coordinator = FeedScrollCoordinator()
        coordinator.beginLoadNewer(lastItemID: "a0")

        #expect(coordinator.initialAnchor(isAgentOpened: true) == nil)
    }
}
