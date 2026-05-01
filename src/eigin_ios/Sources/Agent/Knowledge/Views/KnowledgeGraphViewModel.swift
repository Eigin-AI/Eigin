import Foundation
import SwiftUI

/// Manages the state for the ego-centric knowledge graph visualization.
///
/// Loads entity neighborhoods from ``KnowledgeService``, maintains a node cache,
/// handles focus traversal, and drives a ``ForceLayout`` simulation that
/// positions nodes via spring/repulsion physics. New nodes pop in with staggered
/// delays rather than appearing all at once.
@Observable
@MainActor
final class KnowledgeGraphViewModel {
    // MARK: - Public State

    /// All visible nodes, positioned by the force simulation.
    private(set) var nodes: [GraphNode] = []
    /// All visible edges (deduplicated).
    private(set) var edges: [GraphEdge] = []
    /// ID of the currently focused node (center of the graph).
    private(set) var focusID: String?
    /// Whether the initial load is in progress.
    private(set) var isLoading = true
    /// Whether the simulation is still running (animating).
    private(set) var isSimulating = false
    /// Search results from query.
    private(set) var searchResults: [GraphNode] = []

    // MARK: - Private State

    private var nodeCache: [String: GraphNode] = [:]
    /// Maps entity ID to its neighbor IDs.
    private var neighborCache: [String: Set<String>] = [:]

    /// The live force simulation state.
    private var simulation: ForceLayout?
    /// IDs currently in the simulation, in order.
    private var simVisibleIDs: [String] = []
    /// Hop assignment for visible nodes.
    private var simHopMap: [String: Int] = [:]
    /// Timer driving the simulation ticks.
    private var simulationTimer: Timer?
    /// Counter incremented each focus change to cancel stale pop-in tasks.
    private var focusGeneration: Int = 0
    /// Per-node appearance scale (0→1). New nodes start at 0 and ease in.
    private var nodeAppearScale: [String: CGFloat] = [:]
    /// Per-node current display size. Eased toward target each tick for smooth transitions.
    private var nodeDisplaySize: [String: CGFloat] = [:]
    /// Nodes waiting to be revealed, with the simulation tick at which they appear.
    private var pendingAppear: [(id: String, revealAtTick: Int)] = []
    /// Tick counter for the current simulation run (incremented each timer fire).
    private var simTickCount: Int = 0

    private let knowledgeService: any KnowledgeService
    private let agentID: UUID?

    // MARK: - Init

    init(knowledgeService: any KnowledgeService, agentID: UUID?) {
        self.knowledgeService = knowledgeService
        self.agentID = agentID
    }

    deinit {
        MainActor.assumeIsolated {
            simulationTimer?.invalidate()
        }
    }

    // MARK: - Public API

    /// Load the graph starting from the best initial entity.
    func loadInitialGraph() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let startEntity = try await findStartingEntity()
            guard let startEntity else { return }

            let node = makeNode(from: startEntity, hop: 0)
            nodeCache[node.id] = node

            await focusOn(entityID: node.id, animated: false)
        } catch {
            // Graph will be empty — user can still search.
        }
    }

    /// Change focus to a different entity, loading its fresh neighborhood.
    ///
    /// Nodes already on screen stay. New nodes pop in one by one with staggered delays.
    func focusOn(entityID: String, animated: Bool = true) async {
        guard entityID != focusID || nodes.isEmpty else { return }

        // Cancel any in-flight pop-in sequence from a previous focus.
        focusGeneration += 1
        _ = focusGeneration

        // Remember which nodes are currently on screen.
        let previouslyVisible = Set(simVisibleIDs)

        // Clear previous neighborhood — each focus is a clean slate.
        neighborCache.removeAll()

        focusID = entityID

        // Ensure the focus node is in the cache.
        if nodeCache[entityID] == nil {
            await loadEntity(entityID)
        }

        // Load hop-1 neighbors.
        await loadNeighbors(for: entityID)

        // Load hop-2: each hop-1 neighbor's connections.
        let hop1IDs = neighborCache[entityID] ?? []
        for hop1ID in hop1IDs {
            await loadNeighbors(for: hop1ID)
        }

        // Build the full target neighborhood.
        var allIDs: [String] = [entityID]
        var hopMap: [String: Int] = [entityID: 0]

        for neighborID in hop1IDs {
            guard nodeCache[neighborID] != nil else { continue }
            allIDs.append(neighborID)
            hopMap[neighborID] = 1
        }
        for hop1ID in hop1IDs {
            let hop2IDs = neighborCache[hop1ID] ?? []
            for hop2ID in hop2IDs {
                guard !hopMap.keys.contains(hop2ID) else { continue }
                guard nodeCache[hop2ID] != nil else { continue }
                allIDs.append(hop2ID)
                hopMap[hop2ID] = 2
            }
        }

        // Split into: nodes already on screen (instant) vs new nodes (staggered reveal).
        let newIDs = allIDs.filter { !previouslyVisible.contains($0) && $0 != entityID }

        // Pre-set new nodes to invisible so the simulation includes them at zero presence.
        if animated {
            for id in newIDs {
                nodeAppearScale[id] = 0
            }
        }

        // Build the simulation ONCE with ALL nodes.
        rebuildSimulation(visibleIDs: allIDs, hopMap: hopMap)

        // Schedule staggered reveals via simulation ticks (no rebuilds needed).
        if animated, !newIDs.isEmpty {
            let shuffled = newIDs.shuffled()
            var tick = 0
            pendingAppear = shuffled.map { id in
                tick += Int.random(
                    in: GraphConfig.popInFrameIntervalMin ... GraphConfig.popInFrameIntervalMax
                )
                return (id: id, revealAtTick: tick)
            }
        } else {
            pendingAppear = []
        }
    }

    /// Search for entities by name/content.
    func search(query: String) async {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            searchResults = []
            return
        }

        do {
            let types = ["actor", "thing", "fact", "output", "note"]
            var results: [GraphNode] = []

            for type in types {
                let ids = try await knowledgeService.listEntities(
                    type: type, spaceID: nil, agentID: agentID
                )
                for id in ids {
                    if let entity = try await knowledgeService.getEntity(
                        type: type, id: id, spaceID: nil, agentID: agentID
                    ) {
                        let name = Self.primaryField(for: entity)
                        if name.localizedCaseInsensitiveContains(query)
                            || entity.id.localizedCaseInsensitiveContains(query)
                        {
                            let node = makeNode(from: entity, hop: 0)
                            results.append(node)
                        }
                    }
                }
            }

            searchResults = results
        } catch {
            searchResults = []
        }
    }

    /// Clear search results.
    func clearSearch() {
        searchResults = []
    }

    /// Get the full entity for the detail sheet.
    func getEntity(id: String) async -> FirmEntity? {
        let parts = id.split(separator: ".", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        let type = String(parts[0])
        let shortID = String(parts[1])
        return try? await knowledgeService.getEntity(
            type: type, id: shortID, spaceID: nil, agentID: agentID
        )
    }

    /// Remove a deleted entity from the graph and re-focus if needed.
    func handleEntityDeleted(id: String) async {
        nodeCache.removeValue(forKey: id)
        neighborCache.removeValue(forKey: id)
        nodeAppearScale.removeValue(forKey: id)
        nodeDisplaySize.removeValue(forKey: id)
        pendingAppear.removeAll { $0.id == id }

        // Remove from other nodes' neighbor lists.
        for key in neighborCache.keys {
            neighborCache[key]?.remove(id)
        }

        if id == focusID {
            // Re-focus on first hop-1 neighbor, or reload from scratch.
            let hop1Neighbors = simVisibleIDs.filter { simHopMap[$0] == 1 && $0 != id }
            if let next = hop1Neighbors.first {
                await focusOn(entityID: next)
            } else {
                await loadInitialGraph()
            }
        } else {
            // Rebuild simulation without the deleted node.
            let newIDs = simVisibleIDs.filter { $0 != id }
            rebuildSimulation(visibleIDs: newIDs, hopMap: simHopMap)
        }
    }

    // MARK: - Simulation

    /// Build (or rebuild) the force simulation with the given visible nodes.
    private func rebuildSimulation(visibleIDs: [String], hopMap: [String: Int]) {
        simulationTimer?.invalidate()
        simTickCount = 0

        let visibleSet = Set(visibleIDs)

        // Build index map.
        var indexMap: [String: Int] = [:]
        let nodeInputs: [(id: String, hop: Int)] = visibleIDs.enumerated().map { index, id in
            indexMap[id] = index
            return (id: id, hop: hopMap[id] ?? 1)
        }

        // Build edges.
        var edgePairs: [(sourceIndex: Int, targetIndex: Int)] = []
        var edgeSet: Set<String> = []

        for nodeID in visibleIDs {
            let neighbors = neighborCache[nodeID] ?? []
            for neighborID in neighbors where visibleSet.contains(neighborID) {
                let edgeKey =
                    nodeID < neighborID ? "\(nodeID)->\(neighborID)" : "\(neighborID)->\(nodeID)"
                guard edgeSet.insert(edgeKey).inserted else { continue }
                guard let si = indexMap[nodeID], let ti = indexMap[neighborID] else { continue }
                edgePairs.append((sourceIndex: si, targetIndex: ti))
            }
        }

        // Capture current positions so existing nodes stay put.
        var previousPositions: [String: CGPoint] = [:]
        if let sim = simulation {
            for simNode in sim.nodes {
                previousPositions[simNode.id] = simNode.position
            }
        }

        // Seed appear scale for new nodes (0 = invisible, eases toward 1).
        // The focus node always appears at full scale immediately.
        for id in visibleIDs {
            if nodeAppearScale[id] == nil {
                let isFocus = id == focusID
                nodeAppearScale[id] = (previousPositions.isEmpty || isFocus) ? 1.0 : 0.0
            }
        }
        // Seed display sizes for new nodes at their target size (no initial animation).
        for id in visibleIDs {
            if nodeDisplaySize[id] == nil {
                nodeDisplaySize[id] = Self.targetSize(for: hopMap[id] ?? 1)
            }
        }

        // Clean up scales/sizes for nodes no longer visible.
        let visibleIDSet = Set(visibleIDs)
        nodeAppearScale = nodeAppearScale.filter { visibleIDSet.contains($0.key) }
        nodeDisplaySize = nodeDisplaySize.filter { visibleIDSet.contains($0.key) }

        // Build visible edges for rendering — only between nodes that are already visible
        // (scale > 0). Edges to pending nodes are added later via rebuildEdges().
        let renderedSet = Set(visibleIDs.filter { (nodeAppearScale[$0] ?? 0) > 0 })
        var resultEdges: [GraphEdge] = []
        edgeSet.removeAll()
        for nodeID in visibleIDs where renderedSet.contains(nodeID) {
            let neighbors = neighborCache[nodeID] ?? []
            for neighborID in neighbors where renderedSet.contains(neighborID) {
                let edge = GraphEdge(from: nodeID, to: neighborID)
                if edgeSet.insert(edge.id).inserted {
                    resultEdges.append(edge)
                }
            }
        }
        edges = resultEdges

        // Create simulation, seeding existing nodes at their current positions and presence.
        simulation = ForceLayout(
            nodeIDs: nodeInputs,
            edges: edgePairs,
            previousPositions: previousPositions,
            initialPresence: nodeAppearScale
        )

        // First load: fast-forward so it doesn't start from random chaos.
        if previousPositions.isEmpty {
            for _ in 0 ..< GraphConfig.initialFastForwardTicks {
                simulation?.tick()
            }
        }

        simVisibleIDs = visibleIDs
        simHopMap = hopMap
        syncPositionsFromSimulation()

        // Start/restart the physics timer.
        isSimulating = true
        simulationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) {
            [weak self] _ in
            MainActor.assumeIsolated {
                self?.simulationTick()
            }
        }
    }

    private func simulationTick() {
        guard var sim = simulation else {
            stopSimulation()
            return
        }

        simTickCount += 1

        // Reveal pending nodes whose scheduled tick has arrived.
        var edgesChanged = false
        if !pendingAppear.isEmpty {
            let ready = pendingAppear.prefix(while: { $0.revealAtTick <= simTickCount })
            if !ready.isEmpty {
                for item in ready {
                    nodeAppearScale[item.id] = GraphConfig.appearScaleStep
                    if let idx = simVisibleIDs.firstIndex(of: item.id) {
                        sim.nodes[idx].presence = GraphConfig.appearScaleStep
                    }
                }
                pendingAppear.removeFirst(ready.count)
                edgesChanged = true
            }
        }

        // Ease appear scales toward 1 (~12 frames to full size at 60fps).
        // Only nodes with scale > 0 (already revealed) get eased in.
        // Nodes still at 0 are waiting in pendingAppear for their reveal tick.
        for (index, id) in simVisibleIDs.enumerated() {
            if let current = nodeAppearScale[id], current > 0, current < 1.0 {
                let newScale = min(1.0, current + GraphConfig.appearScaleStep)
                nodeAppearScale[id] = newScale
                sim.nodes[index].presence = newScale
            }
        }

        // Ease display sizes toward their hop's target size.
        let sizeEaseSpeed: CGFloat = GraphConfig.sizeEaseSpeed
        for id in simVisibleIDs {
            let target = Self.targetSize(for: simHopMap[id] ?? 1)
            let current = nodeDisplaySize[id] ?? target
            if abs(current - target) > 0.5 {
                nodeDisplaySize[id] = current + (target - current) * sizeEaseSpeed
            } else {
                nodeDisplaySize[id] = target
            }
        }

        sim.tick()
        simulation = sim

        // Rebuild rendered edges when new nodes become visible.
        if edgesChanged {
            rebuildEdges()
        }

        syncPositionsFromSimulation()

        let allAppeared = pendingAppear.isEmpty
        if allAppeared, sim.isSettled || sim.tickCount > GraphConfig.maxSimulationTicks {
            stopSimulation()
        }
    }

    /// Rebuild just the rendered edge array from current visible nodes with non-zero presence.
    private func rebuildEdges() {
        let visibleSet = Set(
            simVisibleIDs.filter { (nodeAppearScale[$0] ?? 0) > 0 }
        )
        var edgeSet: Set<String> = []
        var resultEdges: [GraphEdge] = []
        for nodeID in simVisibleIDs where visibleSet.contains(nodeID) {
            let neighbors = neighborCache[nodeID] ?? []
            for neighborID in neighbors where visibleSet.contains(neighborID) {
                let edge = GraphEdge(from: nodeID, to: neighborID)
                if edgeSet.insert(edge.id).inserted {
                    resultEdges.append(edge)
                }
            }
        }
        edges = resultEdges
    }

    private func stopSimulation() {
        simulationTimer?.invalidate()
        simulationTimer = nil
        isSimulating = false
    }

    private func syncPositionsFromSimulation() {
        guard let sim = simulation else { return }

        // Build positions array first for crowding calculation.
        let positions = sim.nodes.map(\.position)
        let crowdingRadiusSq = GraphConfig.labelCrowdingRadius * GraphConfig.labelCrowdingRadius

        var resultNodes: [GraphNode] = []
        for (index, simNode) in sim.nodes.enumerated() {
            let id = simVisibleIDs[index]
            guard var node = nodeCache[id] else { continue }
            node.hop = simHopMap[id] ?? 1
            node.position = simNode.position
            node.appearScale = nodeAppearScale[id] ?? 1.0
            node.displaySize = nodeDisplaySize[id] ?? Self.targetSize(for: node.hop)

            // Count nearby nodes for label crowding.
            var nearby = 0
            for (j, otherPos) in positions.enumerated() where j != index {
                let dx = simNode.position.x - otherPos.x
                let dy = simNode.position.y - otherPos.y
                if dx * dx + dy * dy < crowdingRadiusSq {
                    nearby += 1
                }
            }
            node.nearbyCount = nearby

            if let neighbors = neighborCache[id] {
                node = GraphNode(
                    id: node.id,
                    entityType: node.entityType,
                    displayName: node.displayName,
                    isBundled: node.isBundled,
                    relationCount: neighbors.count,
                    hop: node.hop,
                    position: node.position,
                    appearScale: node.appearScale,
                    displaySize: node.displaySize,
                    nearbyCount: node.nearbyCount
                )
            }
            resultNodes.append(node)
        }
        nodes = resultNodes
    }

    // MARK: - Data Loading

    private func findStartingEntity() async throws -> FirmEntity? {
        let types = ["actor", "thing", "fact", "output", "note"]
        var bestEntity: FirmEntity?
        var bestRelCount = -1

        for type in types {
            let ids = try await knowledgeService.listEntities(
                type: type, spaceID: nil, agentID: agentID
            )
            for id in ids {
                guard
                    let entity = try await knowledgeService.getEntity(
                        type: type, id: id, spaceID: nil, agentID: agentID
                    )
                else { continue }

                if entity.id == "actor.user" {
                    return entity
                }

                // Prefer actor entities (user's actor).
                if type == "actor", bestEntity?.entityType != "actor" {
                    bestEntity = entity
                    let related = try await knowledgeService.getRelated(
                        type: type, id: id, direction: .both, spaceID: nil, agentID: agentID
                    )
                    bestRelCount = related.count
                    continue
                }

                let related = try await knowledgeService.getRelated(
                    type: type, id: id, direction: .both, spaceID: nil, agentID: agentID
                )
                if related.count > bestRelCount, bestEntity?.entityType != "actor" {
                    bestEntity = entity
                    bestRelCount = related.count
                }
            }
        }

        return bestEntity
    }

    /// Fetch and cache a single entity by qualified ID.
    private func loadEntity(_ entityID: String) async {
        let parts = entityID.split(separator: ".", maxSplits: 1)
        guard parts.count == 2 else { return }
        let type = String(parts[0])
        let shortID = String(parts[1])
        if let entity = try? await knowledgeService.getEntity(
            type: type, id: shortID, spaceID: nil, agentID: agentID
        ) {
            let node = makeNode(from: entity, hop: 0)
            nodeCache[node.id] = node
        }
    }

    private func loadNeighbors(for entityID: String) async {
        guard neighborCache[entityID] == nil else { return }

        let parts = entityID.split(separator: ".", maxSplits: 1)
        guard parts.count == 2 else { return }
        let type = String(parts[0])
        let shortID = String(parts[1])

        do {
            let related = try await knowledgeService.getRelated(
                type: type, id: shortID, direction: .both, spaceID: nil, agentID: agentID
            )

            var neighborIDs: Set<String> = []
            for relatedEntity in related {
                let node = makeNode(from: relatedEntity, hop: 1)
                nodeCache[node.id] = nodeCache[node.id] ?? node
                neighborIDs.insert(node.id)
            }
            neighborCache[entityID] = neighborIDs

            if var cached = nodeCache[entityID] {
                cached = GraphNode(
                    id: cached.id,
                    entityType: cached.entityType,
                    displayName: cached.displayName,
                    isBundled: cached.isBundled,
                    relationCount: neighborIDs.count,
                    hop: cached.hop,
                    position: cached.position
                )
                nodeCache[entityID] = cached
            }
        } catch {
            neighborCache[entityID] = []
        }
    }

    private func makeNode(from entity: FirmEntity, hop: Int) -> GraphNode {
        let name = Self.primaryField(for: entity)
        let isBundled = Self.isBundledEntity(entity)
        let relCount = Self.estimateRelationCount(entity)
        return GraphNode(
            id: entity.id,
            entityType: entity.entityType,
            displayName: name,
            isBundled: isBundled,
            relationCount: relCount,
            hop: hop,
            position: .zero
        )
    }

    // MARK: - Helpers

    /// Target display diameter for a given hop level.
    static func targetSize(for hop: Int) -> CGFloat {
        switch hop {
        case 0: GraphConfig.focusNodeSize
        case 1: GraphConfig.hop1NodeSize
        default: GraphConfig.hop2NodeSize
        }
    }

    static func primaryField(for entity: FirmEntity) -> String {
        for fieldName in ["name", "claim", "content"] {
            if let field = entity.fields.first(where: { $0.name == fieldName }),
               case .string(let value) = field.value,
               !value.isEmpty
            {
                return value.count > 40 ? String(value.prefix(40)) + "..." : value
            }
        }
        return entity.id
    }

    private static func isBundledEntity(_ entity: FirmEntity) -> Bool {
        let shortID = extractShortID(from: entity.id, type: entity.entityType)
        let bundledPath = BundledKnowledge.entityPath(
            prefix: BundledKnowledge.bundledPrefix,
            type: entity.entityType,
            id: shortID
        )
        return BundledKnowledge.allSources.contains { $0.path == bundledPath }
    }

    static func extractShortID(from qualifiedID: String, type: String) -> String {
        let prefix = type + "."
        return qualifiedID.hasPrefix(prefix)
            ? String(qualifiedID.dropFirst(prefix.count)) : qualifiedID
    }

    private static func estimateRelationCount(_ entity: FirmEntity) -> Int {
        let relFields: Set = ["relates_to", "belongs_to", "uses", "describes"]
        var count = 0
        for field in entity.fields where relFields.contains(field.name) {
            if case .list(let items) = field.value {
                count += items.count
            } else if case .entityReference = field.value {
                count += 1
            }
        }
        return count
    }
}
