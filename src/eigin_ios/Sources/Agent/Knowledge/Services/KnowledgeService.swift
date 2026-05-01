import Foundation
import SwiftData

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
    func isBundled(path: String) -> Bool
    func getSource(path: String, spaceID: UUID?, agentID: UUID?) async throws -> String?
    func findEntitySource(type: String, id: String, spaceID: UUID?, agentID: UUID?) async throws
        -> String?
    func getSchema(entityType: String, spaceID: UUID?, agentID: UUID?) async throws -> FirmSchema?
    func getFirmSource(type: String, id: String, spaceID: UUID?, agentID: UUID?) async throws
        -> FirmSource?
    func allVisibleSources(spaceID: UUID?, agentID: UUID?) async throws -> [FirmSource]
    func validEntities(type: String, spaceID: UUID?, agentID: UUID?, at date: Date) async throws
        -> [FirmEntity]
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

        return "\(type).\(id)"
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
        let dsl = try session.generateEntityDsl(entity: entity)

        let shortID = entity.id.hasPrefix("\(entity.entityType).")
            ? String(entity.id.dropFirst(entity.entityType.count + 1))
            : entity.id
        let targetPath = BundledKnowledge.entityPath(
            prefix: BundledKnowledge.knowledgePrefix,
            type: entity.entityType,
            id: shortID
        )

        let context = ModelContext(modelContainer)
        let userSources = try context.fetch(
            FetchDescriptor<FirmSource>(sortBy: [SortDescriptor(\.createdAt)])
        )

        // Validate by building a trial session before persisting.
        let trial = FirmSession()
        for source in BundledKnowledge.allSources {
            try trial.loadSource(content: source.content, path: source.path)
        }
        let targetKey = entityKey(for: targetPath)
        let deduped = visibleSources(
            from: userSources,
            spaceID: spaceID,
            agentID: agentID,
            accessPolicy: activeAccessPolicy
        )
        for source in deduped {
            // Skip any source defining the same entity (regardless of path or scope).
            if entityKey(for: source.path) == targetKey { continue }
            try trial.loadSource(content: source.content, path: source.path)
        }
        try trial.loadSource(content: dsl, path: targetPath)
        try trial.build()

        // Compute embedding for the entity's primary content.
        let embeddingText = KnowledgeEmbedding.embeddingText(for: entity)
        let embedding = EmbeddingHelpers.embed(embeddingText)

        // Validation passed — persist to SwiftData and adopt the trial session.
        let existing = userSources
            .first { $0.path == targetPath && $0.spaceID == spaceID && $0.agentID == agentID }
        if let existing {
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
            context.insert(source)
        }
        try context.save()

        session = trial
        isBuilt = true
    }

    func deleteEntity(type: String, id: String, spaceID: UUID?, agentID: UUID?) async throws {
        // Check if this is a bundled entity.
        let bundledPath = BundledKnowledge.entityPath(
            prefix: BundledKnowledge.bundledPrefix,
            type: type,
            id: id
        )
        if BundledKnowledge.allSources.contains(where: { $0.path == bundledPath }) {
            throw KnowledgeServiceError.cannotDeleteBundled(type: type, id: id)
        }

        // Use the Firm session to find the actual source path for this entity.
        // This is necessary because the Firm parser may normalize IDs (e.g. "v1" → "v_1"),
        // so reconstructing the path from the normalized ID would produce a mismatch.
        try await ensureBuilt(spaceID: spaceID, agentID: agentID)

        guard let sourcePath = try session.findEntitySource(entityType: type, id: id) else {
            throw KnowledgeServiceError.entityNotFound(type: type, id: id)
        }

        // Bundled sources can't be deleted.
        if sourcePath.hasPrefix(BundledKnowledge.bundledPrefix) {
            throw KnowledgeServiceError.cannotDeleteBundled(type: type, id: id)
        }

        let context = ModelContext(modelContainer)
        let allSources = try context.fetch(
            FetchDescriptor<FirmSource>(sortBy: [SortDescriptor(\.createdAt)])
        )

        // Find the FirmSource record matching the session's path, respecting visibility.
        let visible = visibleSources(
            from: allSources,
            spaceID: spaceID,
            agentID: agentID,
            accessPolicy: activeAccessPolicy
        )
        guard let source = visible.first(where: { $0.path == sourcePath }) else {
            throw KnowledgeServiceError.entityNotFound(type: type, id: id)
        }

        context.delete(source)
        try context.save()

        // Rebuild without the deleted entity, preserving the access policy.
        try await rebuild(spaceID: spaceID, agentID: agentID, accessPolicy: activeAccessPolicy)
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
        let targetPath = BundledKnowledge.entityPath(
            prefix: BundledKnowledge.knowledgePrefix,
            type: type,
            id: id
        )
        let context = ModelContext(modelContainer)
        let allSources = try context.fetch(FetchDescriptor<FirmSource>())
        return allSources
            .first { $0.path == targetPath && $0.spaceID == spaceID && $0.agentID == agentID }
            ?? allSources.first { $0.path == targetPath }
    }

    /// Returns all visible FirmSource records for the current scope.
    /// Used by search to compute embedding scores across all knowledge.
    func allVisibleSources(spaceID: UUID?, agentID: UUID?) async throws -> [FirmSource] {
        try await ensureBuilt(spaceID: spaceID, agentID: agentID)
        let context = ModelContext(modelContainer)
        let allSources = try context.fetch(
            FetchDescriptor<FirmSource>(sortBy: [SortDescriptor(\.createdAt)])
        )
        return visibleSources(
            from: allSources,
            spaceID: spaceID,
            agentID: agentID,
            accessPolicy: activeAccessPolicy
        )
    }

    func validEntities(
        type: String,
        spaceID: UUID?,
        agentID: UUID?,
        at date: Date
    ) async throws -> [FirmEntity] {
        let entityIDs = try await listEntities(type: type, spaceID: spaceID, agentID: agentID)
        var result: [FirmEntity] = []
        for entityID in entityIDs {
            guard let entity = try await getEntity(
                type: type,
                id: entityID,
                spaceID: spaceID,
                agentID: agentID
            )
            else { continue }
            if entity.isValid(at: date) {
                result.append(entity)
            }
        }
        return result
    }
}

enum KnowledgeServiceError: LocalizedError {
    case entityNotFound(type: String, id: String)
    case cannotDeleteBundled(type: String, id: String)

    var errorDescription: String? {
        switch self {
        case .entityNotFound(let type, let id):
            "Could not find a deletable source file for \(type).\(id). It may be stored in a legacy multi-entity file that needs manual cleanup."
        case .cannotDeleteBundled(let type, let id):
            "Cannot delete \(type).\(id) because it is a bundled knowledge entry."
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

    func allVisibleSources(spaceID: UUID?, agentID: UUID?) async throws -> [FirmSource] {
        []
    }

    func validEntities(
        type: String,
        spaceID: UUID?,
        agentID: UUID?,
        at date: Date
    ) async throws -> [FirmEntity] {
        []
    }
}
