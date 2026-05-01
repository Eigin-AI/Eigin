import CoreGraphics
import Foundation

/// Central configuration for the knowledge graph visualization.
///
/// All tuning knobs live here so they're easy to find and tweak in one place.
/// Grouped by subsystem: physics, appearance, animation.
enum GraphConfig {
    // MARK: - Physics

    /// Ideal distance for hop-1 nodes from center.
    static let hop1TargetRadius: CGFloat = 160
    /// Ideal distance for hop-2 nodes from center.
    static let hop2TargetRadius: CGFloat = 280
    /// Ideal edge length for springs.
    static let idealEdgeLength: CGFloat = 140

    /// Base repulsion strength between nodes. Scaled by the sum of node radii
    /// so larger nodes push harder and maintain appropriate spacing.
    static let repulsionStrength: CGFloat = 8000

    /// Spring stiffness for edges.
    static let springStiffness: CGFloat = 0.03
    /// How strongly the radial bias pulls nodes to their target orbit.
    static let radialStrength: CGFloat = 0.05
    /// Center gravity strength for the focus node.
    static let centerGravity: CGFloat = 0.2

    /// Velocity damping per tick (0..1, lower = more damping).
    static let damping: CGFloat = 0.4
    /// Velocity below which a node is considered settled.
    static let settleThreshold: CGFloat = 0.5
    /// Number of ticks to fast-forward on first load.
    static let initialFastForwardTicks: Int = 30
    /// Maximum ticks before stopping the simulation.
    static let maxSimulationTicks: Int = 500

    // MARK: - Node Appearance

    /// Node diameter for the focus node (hop 0).
    static let focusNodeSize: CGFloat = 80
    /// Node diameter for hop-1 neighbors.
    static let hop1NodeSize: CGFloat = 40
    /// Node diameter for hop-2 neighbors.
    static let hop2NodeSize: CGFloat = 25

    /// Fill opacity for the focus node.
    static let focusNodeOpacity: Double = 1.0
    /// Fill opacity for hop-1 neighbors.
    static let hop1NodeOpacity: Double = 0.8
    /// Fill opacity for hop-2 neighbors.
    static let hop2NodeOpacity: Double = 0.5

    /// Icon size as a fraction of node diameter.
    static let iconSizeRatio: CGFloat = 0.4
    /// Icon opacity for hop-2 nodes (hop 0/1 use 1.0).
    static let hop2IconOpacity: Double = 0.7

    // MARK: - Edge Appearance

    /// Edge opacity for first-degree connections.
    static let hop1EdgeOpacity: Double = 0.8
    /// Edge opacity for second-degree connections.
    static let hop2EdgeOpacity: Double = 0.4
    /// Line width for first-degree edges.
    static let hop1EdgeWidth: CGFloat = 1.0
    /// Line width for second-degree edges.
    static let hop2EdgeWidth: CGFloat = 0.5

    // MARK: - Animation

    /// How much `appearScale` increases per frame (60fps). ~12 frames to full.
    static let appearScaleStep: CGFloat = 0.08
    /// Min delay between staggered node pop-ins (seconds).
    static let popInDelayMin: Double = 0.03
    /// Max delay between staggered node pop-ins (seconds).
    static let popInDelayMax: Double = 0.08
    /// Min frame gap between pop-in reveals (at 60fps).
    static let popInFrameIntervalMin: Int = 2
    /// Max frame gap between pop-in reveals (at 60fps).
    static let popInFrameIntervalMax: Int = 5
    /// How fast display size eases toward target each tick (0→1, higher = faster).
    static let sizeEaseSpeed: CGFloat = 0.15
    /// Minimum appear scale before icon is drawn.
    static let iconAppearThreshold: CGFloat = 0.3
    /// Minimum appear scale before label is drawn.
    static let labelAppearThreshold: CGFloat = 0.5

    // MARK: - Labels

    /// Minimum rendered node size (in points, after zoom) for the label to appear.
    /// Focus node ignores this — its label is always visible.
    static let labelMinNodeSize: CGFloat = 28
    /// Radius (in layout points) to count nearby nodes for crowding detection.
    static let labelCrowdingRadius: CGFloat = 140
    /// If a node has more than this many neighbors within the crowding radius, hide its label.
    static let labelCrowdingThreshold: Int = 2

    /// Max label length for focus node.
    static let focusLabelMaxLength: Int = 24
    /// Max label length for hop-1 nodes.
    static let hop1LabelMaxLength: Int = 18
    /// Max label length for hop-2 nodes.
    static let hop2LabelMaxLength: Int = 12
}
