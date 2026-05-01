@testable import Eigin
import Foundation
import Testing

@Suite("ForceLayout")
struct ForceLayoutTests {
    // MARK: - Basic Simulation

    @Test("Focus node stays near origin after settling")
    func focusNearOrigin() {
        var sim = ForceLayout(
            nodeIDs: [
                (id: "actor.alice", hop: 0),
                (id: "thing.phone", hop: 1),
            ],
            edges: [(sourceIndex: 0, targetIndex: 1)]
        )
        sim.settle()

        let focus = sim.nodes[0]
        let dist = hypot(focus.position.x, focus.position.y)
        #expect(dist < 20, "Focus node should stay near origin, was \(dist)")
    }

    @Test("Hop-1 nodes settle near hop1TargetRadius")
    func hop1Radius() {
        var sim = ForceLayout(
            nodeIDs: [
                (id: "actor.alice", hop: 0),
                (id: "thing.phone", hop: 1),
                (id: "fact.f1", hop: 1),
            ],
            edges: [
                (sourceIndex: 0, targetIndex: 1),
                (sourceIndex: 0, targetIndex: 2),
            ]
        )
        sim.settle()

        for i in 1 ... 2 {
            let dist = hypot(sim.nodes[i].position.x, sim.nodes[i].position.y)
            let target = GraphConfig.hop1TargetRadius
            #expect(abs(dist - target) < 60, "Hop-1 node should be near \(target), was \(dist)")
        }
    }

    @Test("Hop-2 nodes settle further from center than hop-1")
    func hop2FurtherOut() {
        var sim = ForceLayout(
            nodeIDs: [
                (id: "actor.alice", hop: 0),
                (id: "thing.phone", hop: 1),
                (id: "fact.f1", hop: 2),
            ],
            edges: [
                (sourceIndex: 0, targetIndex: 1),
                (sourceIndex: 1, targetIndex: 2),
            ]
        )
        sim.settle()

        let hop1Dist = hypot(sim.nodes[1].position.x, sim.nodes[1].position.y)
        let hop2Dist = hypot(sim.nodes[2].position.x, sim.nodes[2].position.y)
        #expect(
            hop2Dist > hop1Dist,
            "Hop-2 (\(hop2Dist)) should be further than hop-1 (\(hop1Dist))"
        )
    }

    // MARK: - Repulsion

    @Test("Nodes repel each other — no overlap")
    func noOverlap() {
        var sim = ForceLayout(
            nodeIDs: [
                (id: "actor.alice", hop: 0),
                (id: "thing.a", hop: 1),
                (id: "thing.b", hop: 1),
                (id: "thing.c", hop: 1),
                (id: "thing.d", hop: 1),
            ],
            edges: [
                (sourceIndex: 0, targetIndex: 1),
                (sourceIndex: 0, targetIndex: 2),
                (sourceIndex: 0, targetIndex: 3),
                (sourceIndex: 0, targetIndex: 4),
            ]
        )
        sim.settle()

        // Check all hop-1 pairs have meaningful separation.
        for i in 1 ..< 5 {
            for j in (i + 1) ..< 5 {
                let dx = sim.nodes[i].position.x - sim.nodes[j].position.x
                let dy = sim.nodes[i].position.y - sim.nodes[j].position.y
                let dist = hypot(dx, dy)
                #expect(dist > 30, "Nodes \(i) and \(j) too close: \(dist)")
            }
        }
    }

    // MARK: - Settling

    @Test("Simulation settles within max ticks")
    func settles() {
        var sim = ForceLayout(
            nodeIDs: [
                (id: "a", hop: 0),
                (id: "b", hop: 1),
                (id: "c", hop: 1),
            ],
            edges: [
                (sourceIndex: 0, targetIndex: 1),
                (sourceIndex: 0, targetIndex: 2),
            ]
        )
        sim.settle(maxTicks: 200)
        #expect(sim.isSettled)
    }

    // MARK: - Edge Cases

    @Test("Empty simulation is trivially settled")
    func emptySimulation() {
        var sim = ForceLayout(nodeIDs: [], edges: [])
        sim.tick()
        #expect(sim.isSettled)
    }

    @Test("Single node stays at origin")
    func singleNode() {
        var sim = ForceLayout(
            nodeIDs: [(id: "actor.alice", hop: 0)],
            edges: []
        )
        sim.settle()
        let dist = hypot(sim.nodes[0].position.x, sim.nodes[0].position.y)
        #expect(dist < 5)
    }

    @Test("Disconnected hop-1 nodes still repel to spread out")
    func disconnectedRepulsion() {
        var sim = ForceLayout(
            nodeIDs: [
                (id: "a", hop: 0),
                (id: "b", hop: 1),
                (id: "c", hop: 1),
            ],
            edges: [] // No edges — only repulsion and radial bias.
        )
        sim.settle()

        let distB = hypot(sim.nodes[1].position.x, sim.nodes[1].position.y)
        let distC = hypot(sim.nodes[2].position.x, sim.nodes[2].position.y)
        // Both should be pushed outward by repulsion + radial bias.
        #expect(distB > 50)
        #expect(distC > 50)
    }
}
