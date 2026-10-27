import Foundation
import Observation

/// A bounded, one-hop explorer. Page changes never query the knowledge workspace.
@Observable
@MainActor
final class KnowledgeExplorer {
    private(set) var neighborhood: KnowledgeNeighborhood?
    private(set) var root: FirmEntity?
    private(set) var arrivedFrom: String?
    private(set) var page = 0
    private(set) var capacity = 6
    private(set) var isLoading = false
    private(set) var error: (any Error)?

    private let service: any KnowledgeService
    private let agentID: UUID?
    private let spaceID: UUID?
    private var cache: [String: KnowledgeNeighborhood] = [:]
    private var generation = 0
    private enum Request { case initial, focus(FirmEntity, from: String?), refresh }
    private var request: Request = .initial

    init(service: any KnowledgeService, agentID: UUID?, spaceID: UUID? = nil) {
        self.service = service
        self.agentID = agentID
        self.spaceID = spaceID
    }

    var neighbors: [FirmEntity] {
        let neighbors = neighborhood?.neighbors ?? []
        guard let arrivedFrom,
              let previous = neighbors.first(where: { $0.id == arrivedFrom })
        else {
            return neighbors
        }
        return [previous] + neighbors.filter { $0.id != arrivedFrom }
    }

    var pageCount: Int {
        max(1, (neighbors.count + capacity - 1) / capacity)
    }

    var visibleNeighbors: [FirmEntity] {
        Array(neighbors.dropFirst(page * capacity).prefix(capacity))
    }

    func setCapacity(_ value: Int) {
        capacity = value <= 4 ? 4 : 6
        page = min(page, pageCount - 1)
    }

    func setPage(_ value: Int) {
        page = min(max(0, value), pageCount - 1)
    }

    /// Load the user directly; only scan for a fallback when the user is absent.
    func load() async {
        let ticket = beginLoad(.initial)
        do {
            let entity = try await startingEntity()
            try Task.checkCancellation()
            guard ticket == generation else { return }
            guard let entity else {
                root = nil
                neighborhood = nil
                arrivedFrom = nil
                page = 0
                isLoading = false
                return
            }
            let result = try await fetch(entity)
            try Task.checkCancellation()
            guard ticket == generation else { return }
            root = entity
            commit(result, from: nil)
        } catch {
            fail(error, ticket: ticket)
        }
    }

    /// Keep the old neighborhood visible until the new one is ready.
    func focus(_ entity: FirmEntity) async {
        guard entity.id != neighborhood?.focus.id else { return }
        await navigate(entity, from: neighborhood?.focus.id)
    }

    func reset() async {
        guard let root else { await load(); return }
        await navigate(root, from: nil)
    }

    /// Repeats the failed operation while preserving the current neighborhood.
    func retry() async {
        switch request {
        case .initial: await load()
        case .focus(let entity, let previous): await navigate(entity, from: previous)
        case .refresh: await refresh()
        }
    }

    /// Call after mutations or when returning from detail that may have changed knowledge.
    func refresh() async {
        cache.removeAll()
        guard let focus = neighborhood?.focus else { await load(); return }
        let ticket = beginLoad(.refresh)
        do {
            let current = try await service.getEntity(
                type: focus.entityType, id: KnowledgePresentation.shortID(focus),
                spaceID: spaceID, agentID: agentID
            )
            try Task.checkCancellation()
            guard ticket == generation else { return }
            guard let current else { await load(); return }
            // The focus was retired while the view was open — return to the root.
            if try await service.isRetired(
                type: current.entityType, id: KnowledgePresentation.shortID(current),
                spaceID: spaceID, agentID: agentID
            ) {
                await load()
                return
            }
            let result = try await fetch(current)
            try Task.checkCancellation()
            guard ticket == generation else { return }
            let refreshedRoot: FirmEntity? = if current.id == root?.id {
                current
            } else if let root, let existing = try await service.getEntity(
                type: root.entityType, id: KnowledgePresentation.shortID(root),
                spaceID: spaceID, agentID: agentID
            ) {
                existing
            } else {
                try await startingEntity()
            }
            try Task.checkCancellation()
            guard ticket == generation else { return }
            let oldPage = page
            root = refreshedRoot
            commit(result, from: arrivedFrom)
            setPage(oldPage)
        } catch {
            fail(error, ticket: ticket)
        }
    }

    /// Invalidate suspended requests when the screen leaves; no task owns the view lifetime.
    func cancel() {
        generation += 1
        isLoading = false
    }

    private func navigate(_ entity: FirmEntity, from previous: String?) async {
        let ticket = beginLoad(.focus(entity, from: previous))
        do {
            let result = try await fetch(entity)
            try Task.checkCancellation()
            guard ticket == generation else { return }
            commit(result, from: previous)
        } catch {
            fail(error, ticket: ticket)
        }
    }

    private func beginLoad(_ request: Request) -> Int {
        self.request = request
        generation += 1
        isLoading = true
        error = nil
        return generation
    }

    private func commit(_ result: KnowledgeNeighborhood, from previous: String?) {
        cache[result.focus.id] = result
        neighborhood = result
        arrivedFrom = previous
        page = 0
        isLoading = false
    }

    private func fail(_ failure: any Error, ticket: Int) {
        guard ticket == generation else { return }
        isLoading = false
        if !(failure is CancellationError) { error = failure }
    }

    private func fetch(_ entity: FirmEntity) async throws -> KnowledgeNeighborhood {
        if let cached = cache[entity.id] { return cached }
        let related = try await service.getRelated(
            type: entity.entityType, id: KnowledgePresentation.shortID(entity), direction: .both,
            spaceID: spaceID, agentID: agentID
        )
        // Relationship rows are derived from the neighbor list, so dropping
        // retired entities removes their rows (including `supersedes`) too.
        var live: [FirmEntity] = []
        for candidate in related {
            if try await service.isRetired(
                type: candidate.entityType, id: KnowledgePresentation.shortID(candidate),
                spaceID: spaceID, agentID: agentID
            ) { continue }
            live.append(candidate)
        }
        return KnowledgeNeighborhood(focus: entity, related: live)
    }

    private func startingEntity() async throws -> FirmEntity? {
        if let user = try await service.getEntity(
            type: "actor", id: "user", spaceID: spaceID, agentID: agentID
        ) { return user }
        // Preserve actor-first, most-connected fallback without relationship queries per entity.
        var best: FirmEntity?
        var bestScore = -1
        for type in KnowledgePresentation.types {
            let ids = try await service.listEntities(type: type, spaceID: spaceID, agentID: agentID)
            for id in ids.sorted() {
                try Task.checkCancellation()
                guard let entity = try await service.getEntity(
                    type: type, id: id, spaceID: spaceID, agentID: agentID
                ) else { continue }
                if try await service.isRetired(
                    type: type, id: id, spaceID: spaceID, agentID: agentID
                ) { continue }
                let references = entity.fields.reduce(0) { count, field in
                    guard KnowledgePresentation.predicates.contains(field.name),
                          case .list(let items) = field.value else { return count }
                    return count + items.count
                }
                let score = (type == "actor" ? 1000 : 0) + references
                if score > bestScore { best = entity; bestScore = score }
            }
        }
        return best
    }
}
