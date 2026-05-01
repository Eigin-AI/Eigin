import CoreGraphics
import Foundation

/// A node in the knowledge graph visualization.
///
/// Value type holding display data and computed position for a single entity.
/// The `hop` level determines visual treatment (size, opacity, label style).
struct GraphNode: Identifiable, Equatable {
    /// Qualified entity ID (e.g. "actor.daniel").
    let id: String
    /// Entity type: actor, thing, fact, output, note.
    let entityType: String
    /// Primary display name (name, claim, or content field).
    let displayName: String
    /// Whether this entity is bundled (seed knowledge).
    let isBundled: Bool
    /// Number of relationships this entity has (used for "+" badge).
    let relationCount: Int
    /// Hop distance from the focus node: 0 = focus, 1 = neighbor, 2 = hop-2.
    var hop: Int
    /// Computed position in the layout coordinate space (origin at focus node).
    var position: CGPoint
    /// Appearance scale (0→1). Animates in on pop-in, out on removal.
    var appearScale: CGFloat = 1.0
    /// Current display diameter in layout points. Eased toward the hop's target size
    /// each simulation tick so size transitions are smooth.
    var displaySize: CGFloat = 0
    /// Number of other nodes within the label crowding radius. Used to suppress labels in dense
    /// areas.
    var nearbyCount: Int = 0

    /// Whether this node has unexplored connections beyond what's visible.
    var hasUnexploredConnections: Bool {
        hop > 0 && relationCount > 1
    }
}
