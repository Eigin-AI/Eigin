import CoreGraphics
import Foundation

/// Force-directed graph layout simulation for the ego-centric knowledge graph.
///
/// All tuning constants live in ``GraphConfig``. The simulation applies four forces
/// each tick: node repulsion, edge springs, radial bias, and center gravity.
struct ForceLayout {
    // MARK: - Simulation State

    struct Node {
        let id: String
        var position: CGPoint
        var velocity: CGPoint
        let hop: Int
        /// Visual radius of this node (half of its display diameter).
        let radius: CGFloat
        /// 0→1 appear progress. Scales how much force this node exerts on others.
        var presence: CGFloat = 1.0
    }

    struct Edge {
        let sourceIndex: Int
        let targetIndex: Int
    }

    var nodes: [Node]
    var edges: [Edge]
    /// The gravity center — the focus node's position. Other nodes orbit around this.
    var gravityCenter: CGPoint

    /// Number of ticks executed so far.
    private(set) var tickCount: Int = 0

    /// Whether all velocities are below the settle threshold.
    var isSettled: Bool {
        nodes.allSatisfy { hypot($0.velocity.x, $0.velocity.y) < GraphConfig.settleThreshold }
    }

    // MARK: - Init

    /// Create a simulation from node descriptors and edge pairs.
    ///
    /// - Parameter previousPositions: Positions from the previous simulation for nodes
    ///   that were already visible. New nodes get a random seed position at their
    ///   hop's target radius.
    init(
        nodeIDs: [(id: String, hop: Int)],
        edges: [(sourceIndex: Int, targetIndex: Int)],
        previousPositions: [String: CGPoint] = [:],
        initialPresence: [String: CGFloat] = [:]
    ) {
        // The gravity center is the focus node's current position (or origin on first load).
        let focusID = nodeIDs.first { $0.hop == 0 }?.id
        let center = focusID.flatMap { previousPositions[$0] } ?? .zero
        gravityCenter = center

        var rng = SystemRandomNumberGenerator()
        nodes = nodeIDs.map { desc in
            let pos: CGPoint
            if let prev = previousPositions[desc.id] {
                pos = prev
            } else {
                switch desc.hop {
                case 0:
                    pos = center
                case 1:
                    let angle = CGFloat.random(in: 0 ..< 2 * .pi, using: &rng)
                    let r = GraphConfig.hop1TargetRadius * CGFloat.random(
                        in: 0.7 ... 1.3,
                        using: &rng
                    )
                    pos = CGPoint(x: center.x + r * cos(angle), y: center.y + r * sin(angle))
                default:
                    let angle = CGFloat.random(in: 0 ..< 2 * .pi, using: &rng)
                    let r = GraphConfig.hop2TargetRadius * CGFloat.random(
                        in: 0.7 ... 1.3,
                        using: &rng
                    )
                    pos = CGPoint(x: center.x + r * cos(angle), y: center.y + r * sin(angle))
                }
            }
            let presence = initialPresence[desc.id] ?? 1.0
            let radius: CGFloat = switch desc.hop {
            case 0: GraphConfig.focusNodeSize / 2
            case 1: GraphConfig.hop1NodeSize / 2
            default: GraphConfig.hop2NodeSize / 2
            }
            return Node(
                id: desc.id,
                position: pos,
                velocity: .zero,
                hop: desc.hop,
                radius: radius,
                presence: presence
            )
        }
        self.edges = edges.map { Edge(sourceIndex: $0.sourceIndex, targetIndex: $0.targetIndex) }
    }

    // MARK: - Tick

    /// Advance the simulation by one step.
    mutating func tick() {
        let n = nodes.count
        guard n > 0 else { return }
        tickCount += 1

        var forces = Array(repeating: CGPoint.zero, count: n)

        // 1. Node-node repulsion — scaled by the sum of radii so bigger nodes push harder.
        let baseRadius = GraphConfig.hop2NodeSize / 2 // smallest node = 1x multiplier
        for i in 0 ..< n {
            for j in (i + 1) ..< n {
                let dx = nodes[i].position.x - nodes[j].position.x
                let dy = nodes[i].position.y - nodes[j].position.y
                let distSq = max(dx * dx + dy * dy, 1)
                let dist = sqrt(distSq)
                // Size-based multiplier: sum of radii relative to the smallest node pair.
                let radiusSum = nodes[i].radius + nodes[j].radius
                let sizeMultiplier = radiusSum / baseRadius
                // Scale force by how "present" each node is — newly appearing nodes exert less
                // force.
                let presence = min(nodes[i].presence, nodes[j].presence)
                let force = (GraphConfig.repulsionStrength * sizeMultiplier * presence) / distSq
                let fx = (dx / dist) * force
                let fy = (dy / dist) * force
                forces[i].x += fx
                forces[i].y += fy
                forces[j].x -= fx
                forces[j].y -= fy
            }
        }

        // 2. Edge springs.
        for edge in edges {
            let si = edge.sourceIndex
            let ti = edge.targetIndex
            let dx = nodes[ti].position.x - nodes[si].position.x
            let dy = nodes[ti].position.y - nodes[si].position.y
            let dist = max(hypot(dx, dy), 1)
            let displacement = dist - GraphConfig.idealEdgeLength
            let presence = min(nodes[si].presence, nodes[ti].presence)
            let force = GraphConfig.springStiffness * displacement * presence
            let fx = (dx / dist) * force
            let fy = (dy / dist) * force
            forces[si].x += fx
            forces[si].y += fy
            forces[ti].x -= fx
            forces[ti].y -= fy
        }

        // 3. Radial bias — push nodes toward their hop's target orbit around gravityCenter.
        for i in 0 ..< n {
            let node = nodes[i]
            guard node.hop > 0 else { continue }
            let targetR = node.hop == 1 ? GraphConfig.hop1TargetRadius : GraphConfig
                .hop2TargetRadius
            let dx = node.position.x - gravityCenter.x
            let dy = node.position.y - gravityCenter.y
            let dist = max(hypot(dx, dy), 1)
            let displacement = dist - targetR
            let strength = GraphConfig.radialStrength * displacement
            forces[i].x -= (dx / dist) * strength
            forces[i].y -= (dy / dist) * strength
        }

        // 4. Center gravity — pull focus node toward gravityCenter.
        for i in 0 ..< n where nodes[i].hop == 0 {
            forces[i].x -= (nodes[i].position.x - gravityCenter.x) * GraphConfig.centerGravity
            forces[i].y -= (nodes[i].position.y - gravityCenter.y) * GraphConfig.centerGravity
        }

        // Apply forces, damping, and update positions.
        for i in 0 ..< n {
            nodes[i].velocity.x = (nodes[i].velocity.x + forces[i].x) * GraphConfig.damping
            nodes[i].velocity.y = (nodes[i].velocity.y + forces[i].y) * GraphConfig.damping
            nodes[i].position.x += nodes[i].velocity.x
            nodes[i].position.y += nodes[i].velocity.y
        }
    }

    /// Run multiple ticks until settled or max iterations reached.
    mutating func settle(maxTicks: Int = 150) {
        for _ in 0 ..< maxTicks {
            tick()
            if isSettled { break }
        }
    }
}
