import Foundation

/// Centralizes space-scoping decisions for memories and facts.
///
/// Constructed once per turn from the current space context and the set of
/// public (non-private) space IDs. Tools and services call ``canAccess(itemSpaceID:)``
/// instead of implementing their own visibility logic.
struct SpaceAccessPolicy: Equatable {
    let currentSpaceID: UUID?
    let publicSpaceIDs: Set<UUID>

    /// Can the current context see an item scoped to `itemSpaceID`?
    func canAccess(itemSpaceID: UUID?) -> Bool {
        // Global items (nil) are always visible from anywhere
        guard let itemSpace = itemSpaceID else { return true }
        // Items in our own space are always visible
        if itemSpace == currentSpaceID { return true }
        // Public space items are visible from any context
        if publicSpaceIDs.contains(itemSpace) { return true }
        // Private space items from outside that space → hidden
        return false
    }
}
