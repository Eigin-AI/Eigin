import Foundation

/// What produced the latest change to a ``ChatFeed``'s items.
///
/// The scroll/pin logic reads this to react correctly to new items. A trailing
/// user message pins to the top only when the intent is `.sending`; a
/// `.paginating` batch that ends on a user message does not.
enum FeedIntent: Equatable {
    /// Nothing in flight; item changes are incidental (e.g. streaming commits).
    case idle
    /// A user turn was just kicked off (send or retry); pin it to the top.
    case sending
    /// A window batch was loaded or the window snapped; preserve scroll position.
    case paginating
}
