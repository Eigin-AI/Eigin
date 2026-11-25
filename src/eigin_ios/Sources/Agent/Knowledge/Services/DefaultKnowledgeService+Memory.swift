import Foundation
import SwiftData

extension DefaultKnowledgeService {
    /// Soft-hide (`expired = true`) or restore a memory. Expiry is a SwiftData
    /// flag, not part of the Firm DSL, so no rebuild is needed — search reads it
    /// live from the source. Acts on the shadow-winner visible in the scope.
    func setExpired(
        type: String, id: String, expired: Bool, spaceID: UUID?, agentID: UUID?
    ) throws {
        stateLock.lock()
        defer { stateLock.unlock() }
        let (context, source) = try resolveSource(
            type: type, id: id, spaceID: spaceID, agentID: agentID
        )
        source.expired = expired
        source.updatedAt = .now
        try save(context)
        clearVisibleSourcesCache()
    }

    /// Mark or clear the `contested` flag on a memory. Used by consolidation to
    /// stop re-asking about a conflict it already surfaced to the user. Acts on
    /// the shadow-winner visible in the scope; no rebuild needed.
    func setContested(
        type: String, id: String, contested: Bool, spaceID: UUID?, agentID: UUID?
    ) throws {
        stateLock.lock()
        defer { stateLock.unlock() }
        let (context, source) = try resolveSource(
            type: type, id: id, spaceID: spaceID, agentID: agentID
        )
        source.contested = contested
        source.updatedAt = .now
        try save(context)
        clearVisibleSourcesCache()
    }

    func setImportance(
        type: String, id: String, importance: Double, spaceID: UUID?, agentID: UUID?
    ) throws {
        stateLock.lock()
        defer { stateLock.unlock() }
        let (context, source) = try resolveSource(
            type: type, id: id, spaceID: spaceID, agentID: agentID
        )
        source.importance = min(1, max(0, importance))
        source.updatedAt = .now
        try save(context)
        clearVisibleSourcesCache()
    }

    func markReviewed(_ qualifiedIDs: [String], spaceID: UUID?, agentID: UUID?) throws {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard !qualifiedIDs.isEmpty else { return }
        try ensureBuilt(spaceID: spaceID, agentID: agentID)

        // Callers may pass raw or normalized IDs; compare like for like.
        let targets = Set(qualifiedIDs.map { FirmIDNormalization.normalize($0) })
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        let allSources = try context.fetch(
            FetchDescriptor<FirmSource>(sortBy: [SortDescriptor(\.createdAt)])
        )
        let visible = visibleSources(
            from: allSources, spaceID: spaceID, agentID: agentID,
            accessPolicy: activeAccessPolicy
        )
        let now = Date()
        for source in visible where targets.contains(entityKey(for: source.path)) {
            source.lastReviewedAt = now
        }
        try save(context)
        clearVisibleSourcesCache()
    }

    /// Record a retrieval of a memory, bumping its use signals.
    ///
    /// Resolves the shadow-winner ``FirmSource`` for `(type, id)` in the active
    /// scope, increments `accessCount`, and refreshes
    /// `lastAccessedAt`. Debounced per turn: repeat accesses to the same memory
    /// within ``accessDebounceWindow`` are coalesced. Failures are swallowed — access tracking must
    /// never break a retrieval.
    func recordAccess(
        type: String,
        id: String,
        spaceID: UUID?,
        agentID: UUID?
    ) {
        stateLock.lock()
        defer { stateLock.unlock() }
        recordAccess([(type: type, id: id)], spaceID: spaceID, agentID: agentID)
    }

    /// Record retrievals of memories, bumping their use signals in a single
    /// write transaction.
    ///
    /// Resolves the shadow-winner ``FirmSource`` for each `(type, id)` in the
    /// active scope (from the cached snapshot when warm), then applies every
    /// access bump in one background-context save.
    ///
    /// Debounced per turn: repeat accesses to the same memory within
    /// ``accessDebounceWindow`` are coalesced. Failures are swallowed — access tracking must
    /// never break a retrieval.
    func recordAccess(
        _ entities: [(type: String, id: String)],
        spaceID: UUID?,
        agentID: UUID?
    ) {
        stateLock.lock()
        defer { stateLock.unlock() }
        do {
            try ensureBuilt(spaceID: spaceID, agentID: agentID)
        } catch {
            return
        }

        // Count repeated explicit retrievals once within the debounce window.
        let spaceLabel = spaceID?.uuidString ?? "nil"
        let agentLabel = agentID?.uuidString ?? "nil"
        let now = Date()
        let deltas = sharedState.withLock { state -> [String: Double] in
            var deltas: [String: Double] = [:]
            for entity in entities {
                let shortID = entity.id.hasPrefix("\(entity.type).")
                    ? String(entity.id.dropFirst(entity.type.count + 1)) : entity.id
                let targetKey = FirmIDNormalization.normalize("\(entity.type).\(shortID)")
                let debounceKey = "\(spaceLabel)|\(agentLabel)|\(targetKey)"
                if let prior = state.recentAccess[debounceKey],
                   now.timeIntervalSince(prior) < accessDebounceWindow
                {
                    continue
                }
                deltas[targetKey] = 1
            }
            return deltas
        }
        guard !deltas.isEmpty else { return }

        // Update the visible shadow-winning rows.
        guard
            let visible = try? allVisibleSources(spaceID: spaceID, agentID: agentID)
        else { return }
        var winnerIDs: [PersistentIdentifier] = []
        for source in visible where deltas[entityKey(for: source.path)] != nil {
            winnerIDs.append(source.persistentModelID)
        }
        guard !winnerIDs.isEmpty else { return }

        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        let rows = winnerIDs.compactMap { context.model(for: $0) as? FirmSource }
        if rows.count != winnerIDs.count {
            // Access bookkeeping tolerates rows deleted by independent writers.
            AppLogger.warning(
                "KnowledgeService.recordAccess row lookup miss: \(public: winnerIDs.count - rows.count)/\(public: winnerIDs.count)",
                category: .general
            )
        }

        for row in rows {
            guard let delta = deltas[entityKey(for: row.path)] else { continue }
            row.accessCount += delta
            row.lastAccessedAt = now
        }
        do { try save(context) }
        catch { return }
        // Access bookkeeping feeds scoring inputs, so the snapshot is stale now.
        clearVisibleSourcesCache()

        sharedState.withLock { state in
            for targetKey in deltas.keys {
                state.recentAccess["\(spaceLabel)|\(agentLabel)|\(targetKey)"] = now
            }
        }
    }
}
