import Foundation
import SwiftData

extension DefaultKnowledgeService {
    func isBundled(path: String) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return path.hasPrefix(BundledKnowledge.bundledPrefix)
    }

    /// Fetch the SwiftData `FirmSource` record for a given entity.
    /// Used by tools that need access to the embedding or chatID directly.
    func getFirmSource(
        type: String,
        id: String,
        spaceID: UUID?,
        agentID: UUID?
    ) throws -> FirmSource? {
        stateLock.lock()
        defer { stateLock.unlock() }
        try ensureBuilt(spaceID: spaceID, agentID: agentID)
        let rawID = id.hasPrefix("\(type).") ? String(id.dropFirst(type.count + 1)) : id
        let targetKey = FirmIDNormalization.normalize("\(type).\(rawID)")
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        let allSources = try context
            .fetch(FetchDescriptor<FirmSource>(sortBy: [SortDescriptor(\.createdAt)]))
        return visibleSources(
            from: allSources,
            spaceID: spaceID,
            agentID: agentID,
            accessPolicy: activeAccessPolicy
        )
        .first { entityKey(for: $0.path) == targetKey }
    }

    /// Returns recent saved entries using the same visibility and shadowing rules as retrieval.
    func recentSources(
        since: Date, agentID: UUID, accessPolicy: SpaceAccessPolicy, limit: Int
    ) throws -> [String] {
        stateLock.lock()
        defer { stateLock.unlock() }
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        var descriptor = FetchDescriptor<FirmSource>(
            predicate: #Predicate { $0.agentID == nil || $0.agentID == agentID },
            sortBy: [SortDescriptor(\.createdAt), SortDescriptor(\.id)]
        )
        descriptor.fetchLimit = 50
        // Older scoped entries can shadow recent global entries; inspect metadata in pages.
        var winners: [String: FirmSource] = [:]
        while true {
            let page = try context.fetch(descriptor)
            for source in page where accessPolicy.canAccess(itemSpaceID: source.spaceID) {
                let key = entityKey(for: source.path)
                if let previous = winners[key],
                   visibleSources(
                       from: [previous, source],
                       spaceID: nil,
                       agentID: agentID,
                       accessPolicy: accessPolicy
                   ).first?.id == previous.id { continue }
                winners[key] = source
            }
            if page.count < 50 { break }
            descriptor.fetchOffset = (descriptor.fetchOffset ?? 0) + page.count
        }
        return winners.values
            .filter { !$0.expired && $0.updatedAt >= since }
            .sorted {
                $0.updatedAt == $1.updatedAt ? $0.path < $1.path : $0.updatedAt > $1.updatedAt
            }
            .prefix(limit).map {
                let content = String($0.content.prefix(350))
                return "\($0.path) \($0.updatedAt.ISO8601Format()): \(content)"
                    + ($0.content.count > 350 ? " …[truncated]" : "")
            }
    }

    /// Returns all visible FirmSource records for the current scope.
    /// Used by search to compute embedding scores across all knowledge.
    func allVisibleSources(spaceID: UUID?, agentID: UUID?) throws -> [FirmSource] {
        stateLock.lock()
        defer { stateLock.unlock() }
        try ensureBuilt(spaceID: spaceID, agentID: agentID)
        // withLockUnchecked: PersistentModel is not Sendable; the lock serialises access.
        if let cached = sharedState.withLockUnchecked({ $0.visibleSourcesCache }) { return cached }
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        let allSources = try context.fetch(
            FetchDescriptor<FirmSource>(sortBy: [SortDescriptor(\.createdAt)])
        )
        let visible = visibleSources(
            from: allSources,
            spaceID: spaceID,
            agentID: agentID,
            accessPolicy: activeAccessPolicy
        )
        sharedState.withLockUnchecked { $0.visibleSourcesCache = visible }
        return visible
    }
}
