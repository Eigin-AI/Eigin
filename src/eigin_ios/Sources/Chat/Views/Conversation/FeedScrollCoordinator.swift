import SwiftUI

/// Owns a ``ChatFeed``'s scroll and pin state so the feed body stays declarative.
///
/// The core decision is how to react when new items arrive: anchor a pagination
/// batch in place, or pin a newly-sent user message to the top of the viewport.
/// It reads ``FeedIntent`` to tell the two apart, so a paginated batch that ends
/// on a user message is treated as pagination, not a send.
@Observable @MainActor
final class FeedScrollCoordinator {
    /// True while the feed is scrolled to (or near) the bottom.
    private(set) var isAtBottom = true
    /// The user message pinned to the top for the current turn, if any.
    private(set) var pinnedUserMessageID: String?
    /// Measured ScrollView container height; the current-turn block uses it as
    /// `minHeight` so the pinned region always fills at least one viewport.
    var viewportHeight: CGFloat = 0
    /// Item IDs present when the current streaming turn started; anything new
    /// animates in.
    private(set) var preStreamItemIDs: Set<String> = []
    /// False until the feed's one-time reveal at the bottom has run.
    private var hasRevealed = false

    /// Item to anchor a "load newer" batch against, so the batch doesn't pin.
    private var appendAnchorID: String?
    /// What produced the pending item change.
    private var intent: FeedIntent = .idle

    /// The `defaultScrollAnchor` for the feed, picked from the current mode.
    ///
    /// - pagination or a pinned turn → `nil`: neither should be tugged by a
    ///   default anchor. A pending pagination batch is held in place by an
    ///   explicit `scrollTo`, and a `.bottom` default would fight it; an
    ///   active pin would be clipped by `.bottom` re-asserting past it.
    /// - agent-initiated opening (first item isn't a user message) → `.top`:
    ///   a long opening summary shows from its top instead of bottom-anchoring
    ///   past it.
    /// - otherwise → `.bottom`: a normal conversation rests at the latest reply.
    func defaultAnchor(isAgentOpened: Bool) -> UnitPoint? {
        if appendAnchorID != nil { return nil }
        if pinnedUserMessageID != nil { return nil }
        if isAgentOpened { return .top }
        return .bottom
    }

    /// How the feed should react to new trailing items.
    enum ScrollBehavior: Equatable {
        case anchorToBottom(String) // paginated batch: hold this id at the bottom
        case pinToTop(String) // just-sent message: pin this id to the top
        case none
    }

    // MARK: - Intent

    /// Declares the next new item is a user send/retry that should pin to the top.
    func declareSending() {
        intent = .sending
    }

    /// Records that a "load newer" batch is about to arrive; it will anchor to
    /// `lastItemID` rather than pin.
    func beginLoadNewer(lastItemID: String?) {
        appendAnchorID = lastItemID
    }

    // MARK: - Scroll tracking

    func scrollPositionChanged(_ atBottom: Bool) {
        isAtBottom = atBottom
    }

    /// User tapped scroll-to-bottom: release the pin and scroll to the bottom.
    func snapToBottom(proxy: ScrollViewProxy) {
        pinnedUserMessageID = nil
        proxy.scrollTo("bottom-anchor", anchor: .bottom)
    }

    // MARK: - Initial reveal

    /// Whether the feed's one-time reveal rest at the bottom: a normal
    /// conversation opens on its latest message. Skipped for agent-opened
    /// feeds (their `.top` anchor) and an active pin (a send during prewarm
    /// outranks the reveal).
    func shouldRevealAtBottom(isAgentOpened: Bool) -> Bool {
        guard !hasRevealed else { return false }
        hasRevealed = true
        return !isAgentOpened && pinnedUserMessageID == nil
    }

    // MARK: - Item changes

    /// Keeps the reader's place when older messages load in at the top, so the
    /// viewport doesn't jump.
    func restoreScrollAfterOlderLoad(
        oldFirstID: String?, newFirstID: String?, items: [ChatItem], proxy: ScrollViewProxy
    ) {
        guard let oldFirstID, oldFirstID != newFirstID,
              items.contains(where: { $0.id == oldFirstID })
        else { return }
        proxy.scrollTo(oldFirstID, anchor: .top)
    }

    /// Decides how to react to new trailing items and updates state to match.
    /// Pure of SwiftUI so it can be unit-tested without a `ScrollViewProxy`.
    func scrollBehaviorForNewItems(_ items: [ChatItem]) -> ScrollBehavior {
        if let anchorID = appendAnchorID, items.contains(where: { $0.id == anchorID }) {
            appendAnchorID = nil
            return .anchorToBottom(anchorID)
        }
        // Pin only on a send; a pagination batch ending on a user message must not
        // trigger the viewport-sized spacer.
        guard intent == .sending,
              case .message(let id, "user", _, _)? = items.last,
              id != pinnedUserMessageID
        else {
            intent = .idle
            return .none
        }
        intent = .idle
        pinnedUserMessageID = id
        return .pinToTop(id)
    }

    /// Applies the chosen behavior to the scroll view.
    func applyScrollForNewItems(_ items: [ChatItem], proxy: ScrollViewProxy) {
        switch scrollBehaviorForNewItems(items) {
        case .anchorToBottom(let id):
            proxy.scrollTo(id, anchor: .bottom)
        case .pinToTop(let id):
            // Defer one runloop tick so the current-turn block (with its
            // viewport-sized minHeight) is laid out before we scroll.
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo(id, anchor: .top)
                }
            }
        case .none:
            break
        }
    }

    // MARK: - Streaming phase

    /// Captures the pre-stream item set (for grow-in) and resets pin intent on idle.
    func phaseChanged(to phase: StreamThrottler.Phase, items: [ChatItem]) {
        if phase == .waiting {
            if preStreamItemIDs.isEmpty { preStreamItemIDs = Set(items.map(\.id)) }
        } else if phase == .idle {
            preStreamItemIDs = []
            intent = .idle
        }
    }

    /// Whether a row appeared mid-stream and should animate in.
    func isLiveRow(_ id: String, phase: StreamThrottler.Phase) -> Bool {
        phase != .idle && !preStreamItemIDs.isEmpty && !preStreamItemIDs.contains(id)
    }
}
