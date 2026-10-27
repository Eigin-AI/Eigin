import Foundation
import os.lock
import SwiftData

/// How deliberate a knowledge retrieval was. Direct recall (fetch by ID) is a
/// stronger signal of usefulness than being surfaced by search or the hydrator,
/// so it counts for more toward a memory's activation.
enum KnowledgeAccessKind: Sendable {
    case direct
    case indirect

    var weight: Double {
        switch self {
        case .direct: 1.0
        case .indirect: 0.3
        }
    }
}

/// Manages the agent's unified knowledge base backed by Firm.
///
/// Loads bundled schemas and seed entities first, then user/agent-created
/// content from SwiftData, builds the Firm graph, and exposes query and
/// mutation operations.
///
/// Knowledge is scoped to spaces and agents: `spaceID/agentID: nil` means global
/// (visible everywhere). A specific spaceID/agentID means only visible in that
/// space/agent. The graph is rebuilt when the active space or agent changes.
protocol KnowledgeService: Sendable {
    var isBuilt: Bool { get }
    func rebuild(spaceID: UUID?, agentID: UUID?, accessPolicy: SpaceAccessPolicy?) async throws
    func query(_ queryString: String, spaceID: UUID?, agentID: UUID?) async throws
        -> FirmQueryResult
    func getEntity(type: String, id: String, spaceID: UUID?, agentID: UUID?) async throws
        -> FirmEntity?
    func listEntities(type: String, spaceID: UUID?, agentID: UUID?) async throws -> [String]
    func listSchemas(spaceID: UUID?, agentID: UUID?) async throws -> [String]
    func getRelated(
        type: String,
        id: String,
        direction: FirmDirection,
        spaceID: UUID?,
        agentID: UUID?
    ) async throws
        -> [FirmEntity]
    func addEntity(_ entity: FirmEntity, spaceID: UUID?, agentID: UUID?, chatID: UUID?) async throws
    func deleteEntity(type: String, id: String, spaceID: UUID?, agentID: UUID?) async throws
    func setExpired(
        type: String, id: String, expired: Bool, spaceID: UUID?, agentID: UUID?
    ) async throws
    func setContested(
        type: String, id: String, contested: Bool, spaceID: UUID?, agentID: UUID?
    ) async throws
    func setImportance(
        type: String, id: String, importance: Double, spaceID: UUID?, agentID: UUID?
    ) async throws
    /// Stamp `lastReviewedAt` on the given entries (qualified IDs like
    /// `"fact.x"`), marking that consolidation surfaced them this run.
    func markReviewed(_ qualifiedIDs: [String], spaceID: UUID?, agentID: UUID?) async throws
    func isBundled(path: String) -> Bool
    func getSource(path: String, spaceID: UUID?, agentID: UUID?) async throws -> String?
    func findEntitySource(type: String, id: String, spaceID: UUID?, agentID: UUID?) async throws
        -> String?
    func getSchema(entityType: String, spaceID: UUID?, agentID: UUID?) async throws -> FirmSchema?
    func getFirmSource(type: String, id: String, spaceID: UUID?, agentID: UUID?) async throws
        -> FirmSource?
    func recordAccess(
        type: String,
        id: String,
        kind: KnowledgeAccessKind,
        spaceID: UUID?,
        agentID: UUID?
    ) async
    /// Batch variant of ``recordAccess(type:id:kind:spaceID:agentID:)``.
    /// Records several accesses of the same kind in one write transaction.
    func recordAccess(
        _ entities: [(type: String, id: String)],
        kind: KnowledgeAccessKind,
        spaceID: UUID?,
        agentID: UUID?
    ) async
    func allVisibleSources(spaceID: UUID?, agentID: UUID?) async throws -> [FirmSource]
    func unexpiredEntities(type: String, spaceID: UUID?, agentID: UUID?) async throws
        -> [FirmEntity]
    /// Whether a memory is hidden from the knowledge views: its source is
    /// soft-hidden (expired), or an active entry supersedes it via a
    /// `supersedes` edge. Search keeps its own include_expired path; this
    /// gates presentation only (graph, list, detail).
    func isRetired(type: String, id: String, spaceID: UUID?, agentID: UUID?) async throws
        -> Bool
}

/// Default implementation backed by a ``FirmSession`` and SwiftData persistence.
@Observable
final class DefaultKnowledgeService: KnowledgeService, @unchecked Sendable {
    private(set) var isBuilt = false
    private var session = FirmSession()
    private var activeSpaceID: UUID?
    private var activeAgentID: UUID?
    private var activeAccessPolicy: SpaceAccessPolicy?
    private let modelContainer: ModelContainer

    /// Hot-path mutable state: the debounce table and the visible-source
    /// snapshot. Lock-guarded because tools, hydrator, and background passes
    /// hit this class concurrently from different tasks.
    ///
    /// `@unchecked` because it stores `PersistentModel` references, which
    /// SwiftData excludes from Sendable; access is serialised by the lock and
    /// the models are only read for fields, as elsewhere in this class.
    private struct SharedState: @unchecked Sendable {
        var recentAccess: [String: (weight: Double, at: Date)] = [:]
        /// Cached visible-source snapshot for the active scope. One fetch
        /// serves every read in an operation (a search runs six scope
        /// scans). Cleared on any source save — including recordAccess, since
        /// scoring reads `accessCount`/`lastAccessedAt` off the snapshot.
        var visibleSourcesCache: [FirmSource]?
    }

    private let sharedState = OSAllocatedUnfairLock(initialState: SharedState())

    /// Clears the visible-source snapshot. Called after bulk replaces of
    /// FirmSource rows that bypass this service (such as the debug data
    /// import), and internally after every source save.
    func invalidateVisibleSourcesCache() {
        sharedState.withLock { $0.visibleSourcesCache = nil }
    }

    /// Window within which repeat accesses to the same entry are coalesced.
    /// Sized to span a single agent turn (surface then fetch), not real elapsed
    /// use across turns.
    private let accessDebounceWindow: TimeInterval = 90

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    // MARK: - Scope resolution

    /// Returns a specificity score for a source relative to the active scope.
    /// Higher = more specific: +2 for matching spaceID, +1 for matching agentID.
    private func scopeSpecificity(_ source: FirmSource, spaceID: UUID?, agentID: UUID?) -> Int {
        var score = 0
        if let sid = source.spaceID, sid == spaceID { score += 2 }
        if let aid = source.agentID, aid == agentID { score += 1 }
        return score
    }

    /// Extract the entity's qualified ID ("actor.daniel") from a source path.
    ///
    /// Path format: `{prefix}/{type}/{id}.firm` → qualified ID is `{type}.{id}`.
    /// Handles malformed paths where the ID already contains the type prefix
    /// (e.g. `actor/actor.daniel.firm` → still returns `actor.daniel`).
    ///
    /// The result is Firm-normalized (snake_case): the graph normalizes every
    /// ID (`"v1"` → `"v_1"`), so keys derived from paths must match keys built
    /// from graph IDs or the same entity appears twice (see #285).
    private func entityKey(for path: String) -> String {
        // Strip prefix and ".firm" to get "type/id".
        var stripped = path
            .replacingOccurrences(of: BundledKnowledge.knowledgePrefix, with: "")
            .replacingOccurrences(of: BundledKnowledge.bundledPrefix, with: "")
        if stripped.hasSuffix(".firm") {
            stripped = String(stripped.dropLast(5))
        }

        // Split into type and id components.
        let parts = stripped.split(separator: "/", maxSplits: 1)
        guard parts.count == 2 else { return stripped }

        let type = String(parts[0])
        var id = String(parts[1])

        // Strip redundant type prefix from the id (e.g. "actor.daniel" → "daniel"
        // when type is already "actor").
        if id.hasPrefix("\(type).") {
            id = String(id.dropFirst(type.count + 1))
        }

        return FirmIDNormalization.normalize("\(type).\(id)")
    }

    /// Filters sources to those visible in the given scope, then deduplicates
    /// keeping only the most-specific source for each entity (space overrides global).
    ///
    /// Deduplication uses the entity key (type/id) parsed from the path, not the
    /// raw path, so sources at different paths that define the same entity are
    /// still caught.
    private func visibleSources(
        from sources: [FirmSource],
        spaceID: UUID?,
        agentID: UUID?,
        accessPolicy: SpaceAccessPolicy?
    ) -> [FirmSource] {
        let visible = sources.filter { source in
            let spaceMatch: Bool = if let accessPolicy {
                accessPolicy.canAccess(itemSpaceID: source.spaceID)
            } else {
                source.spaceID == nil || source.spaceID == spaceID
            }
            let agentMatch = source.agentID == nil || source.agentID == agentID
            return spaceMatch && agentMatch
        }

        // Group by entity key, keep the most-specific source for each entity.
        var bestByKey: [String: FirmSource] = [:]
        var bestScore: [String: Int] = [:]
        for source in visible {
            let key = entityKey(for: source.path)
            let score = scopeSpecificity(source, spaceID: spaceID, agentID: agentID)
            if let existing = bestScore[key], existing >= score { continue }
            bestByKey[key] = source
            bestScore[key] = score
        }

        // Preserve original order (createdAt sort from the fetch).
        let winners = Set(bestByKey.values.map(\.id))
        return visible.filter { winners.contains($0.id) }
    }

    // MARK: - Lifecycle

    /// Build the graph if not already built, or rebuild if the scope changed.
    private func ensureBuilt(spaceID: UUID?, agentID: UUID?) async throws {
        if isBuilt, activeSpaceID == spaceID, activeAgentID == agentID { return }
        try await rebuild(spaceID: spaceID, agentID: agentID, accessPolicy: activeAccessPolicy)
    }

    /// Reload all sources and rebuild the graph for the given space/agent scope.
    /// Loads global sources (spaceID/agentID == nil) + sources for the given space/agent.
    func rebuild(
        spaceID: UUID?,
        agentID: UUID?,
        accessPolicy: SpaceAccessPolicy? = nil
    ) async throws {
        session = FirmSession()
        isBuilt = false
        invalidateVisibleSourcesCache()

        let spaceLabel = spaceID.map { String($0.uuidString.prefix(8)) } ?? "nil"
        let agentLabel = agentID.map { String($0.uuidString.prefix(8)) } ?? "nil"
        AppLogger.debug(
            "KnowledgeService.rebuild scope=(space:\(public: spaceLabel), agent:\(public: agentLabel))",
            category: .general
        )

        // 1. Load bundled content (schemas + seed entities).
        for source in BundledKnowledge.allSources {
            try session.loadSource(content: source.content, path: source.path)
        }

        // 2. Load user/agent content from SwiftData: global + current space + current agent.
        //    Deduplicate by entity key so space-scoped knowledge shadows global knowledge.
        let context = ModelContext(modelContainer)
        let userSources = try context.fetch(
            FetchDescriptor<FirmSource>(sortBy: [SortDescriptor(\.createdAt)])
        )

        AppLogger.debug(
            "KnowledgeService.rebuild total FirmSource records: \(public: userSources.count)",
            category: .general
        )

        // Build a default access policy when none is provided, so global/public space
        // sources are visible and private space sources stay hidden.
        let effectivePolicy: SpaceAccessPolicy
        if let accessPolicy {
            effectivePolicy = accessPolicy
        } else {
            let publicSpaces = (try? context.fetch(FetchDescriptor<Space>(
                predicate: #Predicate { $0.isPrivate == false }
            ))) ?? []
            effectivePolicy = SpaceAccessPolicy(
                currentSpaceID: spaceID,
                publicSpaceIDs: Set(publicSpaces.map(\.id))
            )
        }

        let deduped = visibleSources(
            from: userSources,
            spaceID: spaceID,
            agentID: agentID,
            accessPolicy: effectivePolicy
        )

        AppLogger.debug(
            "KnowledgeService.rebuild visible after dedup: \(public: deduped.count) (from \(public: userSources.count) total)",
            category: .general
        )

        for source in deduped {
            try session.loadSource(content: source.content, path: source.path)
        }

        // 3. Build.
        do {
            try session.build()
        } catch {
            AppLogger.error(
                "KnowledgeService.rebuild FAILED: \(public: error.localizedDescription)",
                category: .general
            )
            throw error
        }
        activeSpaceID = spaceID
        activeAgentID = agentID
        activeAccessPolicy = effectivePolicy
        isBuilt = true
        AppLogger.debug("KnowledgeService.rebuild succeeded", category: .general)

        // 4. Backfill embeddings for any FirmSource entries missing them.
        await backfillEmbeddings(sources: deduped, context: context)
    }

    /// Compute and store embeddings for any visible FirmSource records that lack them.
    private func backfillEmbeddings(sources: [FirmSource], context: ModelContext) async {
        var backfilled = 0
        for source in sources {
            guard source.embedding == nil else { continue }
            guard let entity = try? session.getEntity(
                entityType: entityType(from: source.path),
                id: entityID(from: source.path)
            ) else { continue }
            let text = KnowledgeEmbedding.embeddingText(for: entity)
            guard let embedding = EmbeddingHelpers.embed(text) else { continue }
            source.embedding = embedding
            backfilled += 1
        }
        if backfilled > 0 {
            try? context.save()
            AppLogger.debug(
                "KnowledgeService: backfilled \(public: backfilled) embeddings",
                category: .general
            )
        }
    }

    /// Extract entity type from a source path (e.g. "knowledge/actor/daniel.firm" → "actor").
    private func entityType(from path: String) -> String {
        var stripped = path
            .replacingOccurrences(of: BundledKnowledge.knowledgePrefix, with: "")
            .replacingOccurrences(of: BundledKnowledge.bundledPrefix, with: "")
        if stripped.hasSuffix(".firm") { stripped = String(stripped.dropLast(5)) }
        let parts = stripped.split(separator: "/", maxSplits: 1)
        return parts.count >= 1 ? String(parts[0]) : ""
    }

    /// Extract short entity ID from a source path (e.g. "knowledge/actor/daniel.firm" → "daniel").
    private func entityID(from path: String) -> String {
        var stripped = path
            .replacingOccurrences(of: BundledKnowledge.knowledgePrefix, with: "")
            .replacingOccurrences(of: BundledKnowledge.bundledPrefix, with: "")
        if stripped.hasSuffix(".firm") { stripped = String(stripped.dropLast(5)) }
        let parts = stripped.split(separator: "/", maxSplits: 1)
        guard parts.count == 2 else { return stripped }
        let type = String(parts[0])
        var id = String(parts[1])
        if id.hasPrefix("\(type).") { id = String(id.dropFirst(type.count + 1)) }
        return id
    }

    // MARK: - Query

    func query(
        _ queryString: String,
        spaceID: UUID?,
        agentID: UUID?
    ) async throws -> FirmQueryResult {
        try await ensureBuilt(spaceID: spaceID, agentID: agentID)
        return try session.query(queryString: queryString)
    }

    func getEntity(
        type: String,
        id: String,
        spaceID: UUID?,
        agentID: UUID?
    ) async throws -> FirmEntity? {
        try await ensureBuilt(spaceID: spaceID, agentID: agentID)
        return try session.getEntity(entityType: type, id: id)
    }

    func listEntities(type: String, spaceID: UUID?, agentID: UUID?) async throws -> [String] {
        try await ensureBuilt(spaceID: spaceID, agentID: agentID)
        let qualified = try session.listEntities(entityType: type)
        // listEntities returns qualified IDs ("thing.eigin") but callers
        // need short IDs ("eigin") to pass to getEntity/getRelated.
        let prefix = type + "."
        return qualified.map { id in
            id.hasPrefix(prefix) ? String(id.dropFirst(prefix.count)) : id
        }
    }

    func listSchemas(spaceID: UUID?, agentID: UUID?) async throws -> [String] {
        try await ensureBuilt(spaceID: spaceID, agentID: agentID)
        return try session.listSchemas()
    }

    func getRelated(
        type: String,
        id: String,
        direction: FirmDirection,
        spaceID: UUID?,
        agentID: UUID?
    ) async throws -> [FirmEntity] {
        try await ensureBuilt(spaceID: spaceID, agentID: agentID)
        return try session.getRelated(entityType: type, id: id, direction: direction)
    }

    // MARK: - Mutation

    func addEntity(
        _ entity: FirmEntity,
        spaceID: UUID?,
        agentID: UUID?,
        chatID: UUID? = nil
    ) async throws {
        try await ensureBuilt(spaceID: spaceID, agentID: agentID)

        // Canonicalize the ID the same way Firm will at graph-build time
        // ("v1" → "v_1"), so the stored path and DSL always match the graph's
        // view of the entity — however the caller addressed it.
        let rawID = entity.id.hasPrefix("\(entity.entityType).")
            ? String(entity.id.dropFirst(entity.entityType.count + 1))
            : entity.id
        let shortID = FirmIDNormalization.normalize(rawID)
        let targetPath = BundledKnowledge.entityPath(
            prefix: BundledKnowledge.knowledgePrefix,
            type: entity.entityType,
            id: shortID
        )
        let targetKey = entityKey(for: targetPath)
        let canonicalEntity = FirmEntity(
            id: "\(entity.entityType).\(shortID)",
            entityType: entity.entityType,
            fields: entity.fields
        )
        let dsl = try session.generateEntityDsl(entity: canonicalEntity)

        let context = ModelContext(modelContainer)
        let userSources = try context.fetch(
            FetchDescriptor<FirmSource>(sortBy: [SortDescriptor(\.createdAt)])
        )

        // Resolve the shadow-winner row this entity currently lives in, if any.
        // Matching by normalized entity key (not exact path) catches rows
        // stored under a raw ID ("…_v1.firm") when the caller addresses the
        // normalized ID ("…_v_1") — the historical cause of a misleading
        // EntityAlreadyExists on update/supersede (#285).
        let visible = visibleSources(
            from: userSources,
            spaceID: spaceID,
            agentID: agentID,
            accessPolicy: activeAccessPolicy
        )
        let existing = visible.first { entityKey(for: $0.path) == targetKey }
        // Bundled seed entities aren't SwiftData rows, so the winner scan
        // above can't see them — check them by key directly.
        if existing == nil, isBundledEntity(type: entity.entityType, id: shortID) {
            throw KnowledgeServiceError.cannotModifyBundled(
                type: entity.entityType, id: shortID
            )
        }

        // Validate by building a trial session before persisting. If any
        // load/build throws, addEntity throws and nothing is adopted below.
        let trial = FirmSession()
        for source in BundledKnowledge.allSources {
            try trial.loadSource(content: source.content, path: source.path)
        }
        for source in visible {
            // Skip the row being replaced — its entity is redefined by the
            // new DSL under the canonical path.
            if let existing, source.persistentModelID == existing.persistentModelID { continue }
            try trial.loadSource(content: source.content, path: source.path)
        }
        try trial.loadSource(content: dsl, path: targetPath)
        try trial.build()

        // Compute embedding for the entity's primary content.
        let embeddingText = KnowledgeEmbedding.embeddingText(for: canonicalEntity)
        let embedding = EmbeddingHelpers.embed(embeddingText)

        // Validation passed — persist to SwiftData and adopt the trial session.
        // Updates land on the row the caller actually sees (the shadow winner,
        // in its own scope), and migrate its path to the canonical form.
        if let existing {
            existing.path = targetPath
            existing.content = dsl
            existing.chatID = chatID
            existing.embedding = embedding
            existing.updatedAt = .now
        } else {
            let source = FirmSource(
                path: targetPath,
                content: dsl,
                spaceID: spaceID,
                agentID: agentID,
                chatID: chatID
            )
            source.embedding = embedding
            // Treat creation as an implicit first access, so freshly-made
            // entries start with some recency instead of neutral-zero.
            source.accessCount = 1
            source.lastAccessedAt = source.createdAt
            context.insert(source)
        }
        try context.save()

        session = trial
        invalidateVisibleSourcesCache()
        isBuilt = true
    }

    func deleteEntity(type: String, id: String, spaceID: UUID?, agentID: UUID?) async throws {
        // Bundled seed entities aren't SwiftData rows, so resolveSource below
        // can't match them — throw the right error up front.
        if isBundledEntity(type: type, id: id) {
            throw KnowledgeServiceError.cannotDeleteBundled(type: type, id: id)
        }

        let (context, source) = try await resolveSource(
            type: type, id: id, spaceID: spaceID, agentID: agentID
        )

        context.delete(source)
        try context.save()

        // Rebuild without the deleted entity, preserving the access policy.
        try await rebuild(spaceID: spaceID, agentID: agentID, accessPolicy: activeAccessPolicy)
    }

    /// Resolve the shadow-winner ``FirmSource`` for `(type, id)` in the scope.
    ///
    /// Matches by normalized entity key, so callers may pass either the raw or
    /// the Firm-normalized ID ("v1" vs "v_1"); rows stored under a raw-ID path
    /// are still found. Throws `entityNotFound` when no visible row matches.
    private func resolveSource(
        type: String, id: String, spaceID: UUID?, agentID: UUID?
    ) async throws -> (context: ModelContext, source: FirmSource) {
        try await ensureBuilt(spaceID: spaceID, agentID: agentID)
        let context = ModelContext(modelContainer)
        let allSources = try context.fetch(
            FetchDescriptor<FirmSource>(sortBy: [SortDescriptor(\.createdAt)])
        )
        let visible = visibleSources(
            from: allSources, spaceID: spaceID, agentID: agentID,
            accessPolicy: activeAccessPolicy
        )
        let targetKey = FirmIDNormalization.normalize("\(type).\(id)")
        guard let source = visible.first(where: { entityKey(for: $0.path) == targetKey }) else {
            // Bundled seed entities aren't SwiftData rows, so they never show
            // up above — surface the right error instead of "not found".
            if isBundledEntity(type: type, id: id) {
                throw KnowledgeServiceError.cannotModifyBundled(type: type, id: id)
            }
            throw KnowledgeServiceError.entityNotFound(type: type, id: id)
        }
        return (context, source)
    }

    /// Whether a bundled seed entity exists for `(type, id)`, compared by
    /// normalized key so raw and normalized IDs both match.
    private func isBundledEntity(type: String, id: String) -> Bool {
        let targetKey = FirmIDNormalization.normalize("\(type).\(id)")
        return BundledKnowledge.allSources.contains { entityKey(for: $0.path) == targetKey }
    }

    /// Soft-hide (`expired = true`) or restore a memory. Expiry is a SwiftData
    /// flag, not part of the Firm DSL, so no rebuild is needed — search reads it
    /// live from the source. Acts on the shadow-winner visible in the scope.
    func setExpired(
        type: String, id: String, expired: Bool, spaceID: UUID?, agentID: UUID?
    ) async throws {
        let (context, source) = try await resolveSource(
            type: type, id: id, spaceID: spaceID, agentID: agentID
        )
        source.expired = expired
        source.updatedAt = .now
        try context.save()
        invalidateVisibleSourcesCache()
    }

    /// Mark or clear the `contested` flag on a memory. Used by consolidation to
    /// stop re-asking about a conflict it already surfaced to the user. Acts on
    /// the shadow-winner visible in the scope; no rebuild needed.
    func setContested(
        type: String, id: String, contested: Bool, spaceID: UUID?, agentID: UUID?
    ) async throws {
        let (context, source) = try await resolveSource(
            type: type, id: id, spaceID: spaceID, agentID: agentID
        )
        source.contested = contested
        source.updatedAt = .now
        try context.save()
        invalidateVisibleSourcesCache()
    }

    func setImportance(
        type: String, id: String, importance: Double, spaceID: UUID?, agentID: UUID?
    ) async throws {
        let (context, source) = try await resolveSource(
            type: type, id: id, spaceID: spaceID, agentID: agentID
        )
        source.importance = min(1, max(0, importance))
        source.updatedAt = .now
        try context.save()
        invalidateVisibleSourcesCache()
    }

    func markReviewed(_ qualifiedIDs: [String], spaceID: UUID?, agentID: UUID?) async throws {
        guard !qualifiedIDs.isEmpty else { return }
        try await ensureBuilt(spaceID: spaceID, agentID: agentID)

        // Callers may pass raw or normalized IDs; compare like for like.
        let targets = Set(qualifiedIDs.map { FirmIDNormalization.normalize($0) })
        let context = ModelContext(modelContainer)
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
        try context.save()
        invalidateVisibleSourcesCache()
    }

    // MARK: - Source access

    func isBundled(path: String) -> Bool {
        path.hasPrefix(BundledKnowledge.bundledPrefix)
    }

    func getSource(path: String, spaceID: UUID?, agentID: UUID?) async throws -> String? {
        try await ensureBuilt(spaceID: spaceID, agentID: agentID)
        return try session.getSource(path: path)
    }

    func findEntitySource(
        type: String,
        id: String,
        spaceID: UUID?,
        agentID: UUID?
    ) async throws -> String? {
        try await ensureBuilt(spaceID: spaceID, agentID: agentID)
        return try session.findEntitySource(entityType: type, id: id)
    }

    func getSchema(entityType: String, spaceID: UUID?, agentID: UUID?) async throws -> FirmSchema? {
        try await ensureBuilt(spaceID: spaceID, agentID: agentID)
        return try session.getSchema(entityType: entityType)
    }

    /// Fetch the SwiftData `FirmSource` record for a given entity.
    /// Used by tools that need access to the embedding or chatID directly.
    func getFirmSource(
        type: String,
        id: String,
        spaceID: UUID?,
        agentID: UUID?
    ) async throws -> FirmSource? {
        try await ensureBuilt(spaceID: spaceID, agentID: agentID)
        let canonicalID = FirmIDNormalization.normalize(id)
        let targetPath = BundledKnowledge.entityPath(
            prefix: BundledKnowledge.knowledgePrefix,
            type: type,
            id: canonicalID
        )
        let targetKey = "\(type).\(canonicalID)"
        let context = ModelContext(modelContainer)
        let allSources = try context.fetch(FetchDescriptor<FirmSource>())
        // Exact path+scope first; then same path; then normalized-key match,
        // which also catches legacy rows stored under a raw-ID path.
        return allSources
            .first { $0.path == targetPath && $0.spaceID == spaceID && $0.agentID == agentID }
            ?? allSources.first { $0.path == targetPath }
            ?? allSources.first {
                entityKey(for: $0.path) == targetKey
                    && $0.spaceID == spaceID && $0.agentID == agentID
            }
            ?? allSources.first { entityKey(for: $0.path) == targetKey }
    }

    /// Record a retrieval of a memory, bumping its use signals.
    ///
    /// Resolves the shadow-winner ``FirmSource`` for `(type, id)` in the active
    /// scope, adds the access weight to `accessCount`, and refreshes
    /// `lastAccessedAt`. Debounced per turn: repeat accesses to the same memory
    /// within ``accessDebounceWindow`` are coalesced, keeping the strongest kind
    /// (direct beats indirect). Failures are swallowed — access tracking must
    /// never break a retrieval.
    func recordAccess(
        type: String,
        id: String,
        kind: KnowledgeAccessKind,
        spaceID: UUID?,
        agentID: UUID?
    ) async {
        await recordAccess([(type: type, id: id)], kind: kind, spaceID: spaceID, agentID: agentID)
    }

    /// Record retrievals of memories, bumping their use signals in a single
    /// write transaction.
    ///
    /// Resolves the shadow-winner ``FirmSource`` for each `(type, id)` in the
    /// active scope (from the cached snapshot when warm), then applies every
    /// access bump in one background-context save.
    ///
    /// Debounced per turn: repeat accesses to the same memory within
    /// ``accessDebounceWindow`` are coalesced, keeping the strongest kind
    /// (direct beats indirect). Failures are swallowed — access tracking must
    /// never break a retrieval.
    func recordAccess(
        _ entities: [(type: String, id: String)],
        kind: KnowledgeAccessKind,
        spaceID: UUID?,
        agentID: UUID?
    ) async {
        do {
            try await ensureBuilt(spaceID: spaceID, agentID: agentID)
        } catch {
            return
        }

        // Per-turn debounce, keeping the strongest kind. If we already counted
        // this memory this turn at an equal-or-stronger weight, skip; if this
        // access is stronger (indirect → direct), apply only the upgrade delta.
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
                var deltaWeight = kind.weight
                if let prior = state.recentAccess[debounceKey],
                   now.timeIntervalSince(prior.at) < accessDebounceWindow
                {
                    if kind.weight <= prior.weight { continue }
                    deltaWeight = kind.weight - prior.weight
                }
                deltas[targetKey] = deltaWeight
            }
            return deltas
        }
        guard !deltas.isEmpty else { return }

        // Resolve shadow winners from the visible snapshot (cache-warm right
        // after a search), so the write path never needs a full-table fetch.
        guard
            let visible = try? await allVisibleSources(spaceID: spaceID, agentID: agentID)
        else { return }
        var winnerIDs: [PersistentIdentifier] = []
        for source in visible where deltas[entityKey(for: source.path)] != nil {
            winnerIDs.append(source.persistentModelID)
        }
        guard !winnerIDs.isEmpty else { return }

        let context = ModelContext(modelContainer)
        let rows = winnerIDs.compactMap { context.model(for: $0) as? FirmSource }
        if rows.count != winnerIDs.count {
            // Another writer deleted a row between snapshot and write; record
            // what landed rather than failing the whole retrieval.
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
        try? context.save()
        // Access bookkeeping feeds scoring inputs, so the snapshot is stale now.
        invalidateVisibleSourcesCache()

        sharedState.withLock { state in
            for targetKey in deltas.keys {
                state.recentAccess["\(spaceLabel)|\(agentLabel)|\(targetKey)"] = (
                    weight: kind.weight,
                    at: now
                )
            }
        }
    }

    /// Returns all visible FirmSource records for the current scope.
    /// Used by search to compute embedding scores across all knowledge.
    func allVisibleSources(spaceID: UUID?, agentID: UUID?) async throws -> [FirmSource] {
        try await ensureBuilt(spaceID: spaceID, agentID: agentID)
        // withLockUnchecked: PersistentModel is not Sendable; the lock serialises access.
        if let cached = sharedState.withLockUnchecked({ $0.visibleSourcesCache }) { return cached }
        let context = ModelContext(modelContainer)
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

    /// Entities of `type` visible in the scope, excluding soft-hidden
    /// (`expired`) memories. Expiry lives on the `FirmSource` row, resolved to
    /// the shadow winner, so a scoped copy can expire independently.
    func unexpiredEntities(
        type: String,
        spaceID: UUID?,
        agentID: UUID?
    ) async throws -> [FirmEntity] {
        let visible = try await allVisibleSources(spaceID: spaceID, agentID: agentID)
        let expiredKeys = Set(visible.filter(\.expired).map { entityKey(for: $0.path) })
        let entityIDs = try await listEntities(type: type, spaceID: spaceID, agentID: agentID)
        var result: [FirmEntity] = []
        for entityID in entityIDs {
            let shortID = entityID.hasPrefix("\(type).")
                ? String(entityID.dropFirst(type.count + 1)) : entityID
            if expiredKeys.contains("\(type).\(shortID)") { continue }
            guard let entity = try await getEntity(
                type: type, id: entityID, spaceID: spaceID, agentID: agentID
            ) else { continue }
            result.append(entity)
        }
        return result
    }

    func isRetired(type: String, id: String, spaceID: UUID?, agentID: UUID?) async throws -> Bool {
        try await isRetired(type: type, id: id, spaceID: spaceID, agentID: agentID, visited: [])
    }

    private func isRetired(
        type: String,
        id: String,
        spaceID: UUID?,
        agentID: UUID?,
        visited: Set<String>
    ) async throws -> Bool {
        var visited = visited
        let rawID = id.hasPrefix("\(type).") ? String(id.dropFirst(type.count + 1)) : id
        let shortID = FirmIDNormalization.normalize(rawID)
        let key = "\(type).\(shortID)"
        guard visited.insert(key).inserted else { return false }

        let visible = try await allVisibleSources(spaceID: spaceID, agentID: agentID)
        if visible.contains(where: { $0.expired && entityKey(for: $0.path) == key }) {
            return true
        }
        // Explicit result type — the type checker crashes without it.
        let fetched: FirmEntity? = try await getEntity(
            type: type, id: shortID, spaceID: spaceID, agentID: agentID
        )
        guard let fetched else { return false }

        // A `supersedes` edge only retires its target when the predecessor is
        // itself live; already-retired predecessors don't cascade further.
        let incoming = try await getRelated(
            type: fetched.entityType, id: KnowledgePresentation.shortID(fetched),
            direction: .incoming, spaceID: spaceID, agentID: agentID
        )
        let qualifiedKey = FirmIDNormalization.normalize(fetched.id)
        for predecessor in incoming
            where KnowledgeNeighborhood.references(predecessor, predicate: "supersedes")
            .map(FirmIDNormalization.normalize).contains(qualifiedKey)
        {
            if try await !isRetired(
                type: predecessor.entityType,
                id: KnowledgePresentation.shortID(predecessor),
                spaceID: spaceID, agentID: agentID, visited: visited
            ) { return true }
        }
        return false
    }
}

enum KnowledgeServiceError: LocalizedError {
    case entityNotFound(type: String, id: String)
    case cannotDeleteBundled(type: String, id: String)
    case cannotModifyBundled(type: String, id: String)

    var errorDescription: String? {
        switch self {
        case .entityNotFound(let type, let id):
            "Could not find a deletable source file for \(type).\(id). It may be stored in a legacy multi-entity file that needs manual cleanup."
        case .cannotDeleteBundled(let type, let id):
            "Cannot delete \(type).\(id) because it is a bundled knowledge entry."
        case .cannotModifyBundled(let type, let id):
            "Cannot modify \(type).\(id) because it is a bundled knowledge entry."
        }
    }
}

/// No-op implementation used as the environment default and for previews.
struct PreviewKnowledgeService: KnowledgeService {
    var isBuilt: Bool {
        false
    }

    func rebuild(
        spaceID: UUID?,
        agentID: UUID?,
        accessPolicy: SpaceAccessPolicy? = nil
    ) async throws {}
    func query(
        _ queryString: String,
        spaceID: UUID?,
        agentID: UUID?
    ) async throws -> FirmQueryResult {
        .entities(entities: [])
    }

    func getEntity(
        type: String,
        id: String,
        spaceID: UUID?,
        agentID: UUID?
    ) async throws -> FirmEntity? {
        nil
    }

    func listEntities(type: String, spaceID: UUID?, agentID: UUID?) async throws -> [String] {
        []
    }

    func listSchemas(spaceID: UUID?, agentID: UUID?) async throws -> [String] {
        []
    }

    func getRelated(
        type: String,
        id: String,
        direction: FirmDirection,
        spaceID: UUID?,
        agentID: UUID?
    ) async throws -> [FirmEntity] {
        []
    }

    func addEntity(
        _ entity: FirmEntity,
        spaceID: UUID?,
        agentID: UUID?,
        chatID: UUID? = nil
    ) async throws {}
    func deleteEntity(type: String, id: String, spaceID: UUID?, agentID: UUID?) async throws {}
    func setExpired(
        type: String, id: String, expired: Bool, spaceID: UUID?, agentID: UUID?
    ) async throws {}
    func setContested(
        type: String, id: String, contested: Bool, spaceID: UUID?, agentID: UUID?
    ) async throws {}
    func setImportance(
        type: String, id: String, importance: Double, spaceID: UUID?, agentID: UUID?
    ) async throws {}
    func markReviewed(_ qualifiedIDs: [String], spaceID: UUID?, agentID: UUID?) async throws {}
    func isBundled(path: String) -> Bool {
        false
    }

    func getSource(path: String, spaceID: UUID?, agentID: UUID?) async throws -> String? {
        nil
    }

    func findEntitySource(
        type: String,
        id: String,
        spaceID: UUID?,
        agentID: UUID?
    ) async throws -> String? {
        nil
    }

    func getSchema(entityType: String, spaceID: UUID?, agentID: UUID?) async throws -> FirmSchema? {
        nil
    }

    func getFirmSource(
        type: String,
        id: String,
        spaceID: UUID?,
        agentID: UUID?
    ) async throws -> FirmSource? {
        nil
    }

    func recordAccess(
        type: String,
        id: String,
        kind: KnowledgeAccessKind,
        spaceID: UUID?,
        agentID: UUID?
    ) async {}

    func recordAccess(
        _ entities: [(type: String, id: String)],
        kind: KnowledgeAccessKind,
        spaceID: UUID?,
        agentID: UUID?
    ) async {}

    func allVisibleSources(spaceID: UUID?, agentID: UUID?) async throws -> [FirmSource] {
        []
    }

    func unexpiredEntities(
        type: String,
        spaceID: UUID?,
        agentID: UUID?
    ) async throws -> [FirmEntity] {
        []
    }

    func isRetired(type: String, id: String, spaceID: UUID?, agentID: UUID?) async throws -> Bool {
        false
    }
}
