import Foundation
import SwiftData

extension DefaultKnowledgeService {
    func addEntity(
        _ entity: FirmEntity,
        spaceID: UUID?,
        agentID: UUID?,
        chatID: UUID? = nil
    ) throws {
        stateLock.lock()
        defer { stateLock.unlock() }
        try ensureBuilt(spaceID: spaceID, agentID: agentID)

        // Stored paths and DSL use the graph's normalized entity identity.
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
        let dsl = try session.generateEntityDsl(entity: canonicalEntity, sourcePath: targetPath)

        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        let userSources = try context.fetch(
            FetchDescriptor<FirmSource>(sortBy: [SortDescriptor(\.createdAt)])
        )

        // Mutations target the normalized shadow-winning row.
        let visible = visibleSources(
            from: userSources,
            spaceID: spaceID,
            agentID: agentID,
            accessPolicy: activeAccessPolicy
        )
        let existing = visible.first { entityKey(for: $0.path) == targetKey }
        // Bundled seeds are protected separately from SwiftData rows.
        if existing == nil, isBundledEntity(type: entity.entityType, id: shortID) {
            throw KnowledgeServiceError.cannotModifyBundled(
                type: entity.entityType, id: shortID
            )
        }

        let sourceID = existing?.id ?? UUID()
        let replacement = SDK.Source(
            id: sourceID.uuidString, path: targetPath, content: dsl, readOnly: false
        )
        let trial = try SDK.Workspace(sources:
            bundledSources + visible.filter { $0.id != sourceID }
                .map(KnowledgeSDKConversion.source) + [replacement]
        )

        let embeddingText = KnowledgeEmbedding.embeddingText(for: canonicalEntity)
        let embedding = EmbeddingHelpers.embed(embeddingText)

        // Save the shadow-winning row in its own scope before publishing the candidate.
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
            source.id = sourceID
            source.embedding = embedding
            // Creation counts as the first memory access.
            source.accessCount = 1
            source.lastAccessedAt = source.createdAt
            context.insert(source)
        }
        try save(context)

        snapshot = trial
        clearVisibleSourcesCache()
        built = true
    }

    func deleteEntity(type: String, id: String, spaceID: UUID?, agentID: UUID?) throws {
        stateLock.lock()
        defer { stateLock.unlock() }
        // Protect bundled entities before resolving persisted rows.
        if isBundledEntity(type: type, id: id) {
            throw KnowledgeServiceError.cannotDeleteBundled(type: type, id: id)
        }

        let (context, source) = try resolveSource(
            type: type, id: id, spaceID: spaceID, agentID: agentID
        )

        let allSources = try context
            .fetch(FetchDescriptor<FirmSource>(sortBy: [SortDescriptor(\.createdAt)]))
        let remaining = visibleSources(
            from: allSources.filter { $0.id != source.id }, spaceID: spaceID,
            agentID: agentID, accessPolicy: activeAccessPolicy
        )
        let candidate = try buildWorkspace(remaining)
        context.delete(source)
        try save(context)
        snapshot = candidate
        clearVisibleSourcesCache()
    }

    /// Resolve the shadow-winner ``FirmSource`` for `(type, id)` in the scope.
    ///
    /// Matches by normalized entity key, so callers may pass either the raw or
    /// the Firm-normalized ID ("v1" vs "v_1"); rows stored under a raw-ID path
    /// are still found. Throws `entityNotFound` when no visible row matches.
    func resolveSource(
        type: String, id: String, spaceID: UUID?, agentID: UUID?
    ) throws -> (context: ModelContext, source: FirmSource) {
        stateLock.lock()
        defer { stateLock.unlock() }
        try ensureBuilt(spaceID: spaceID, agentID: agentID)
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        let allSources = try context.fetch(
            FetchDescriptor<FirmSource>(sortBy: [SortDescriptor(\.createdAt)])
        )
        let visible = visibleSources(
            from: allSources, spaceID: spaceID, agentID: agentID,
            accessPolicy: activeAccessPolicy
        )
        let targetKey = FirmIDNormalization.normalize("\(type).\(id)")
        guard let source = visible.first(where: { entityKey(for: $0.path) == targetKey }) else {
            // Bundled entities report protection errors.
            if isBundledEntity(type: type, id: id) {
                throw KnowledgeServiceError.cannotModifyBundled(type: type, id: id)
            }
            throw KnowledgeServiceError.entityNotFound(type: type, id: id)
        }
        return (context, source)
    }

    /// Whether a bundled seed entity exists for `(type, id)`, compared by
    /// normalized key so raw and normalized IDs both match.
    func isBundledEntity(type: String, id: String) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        let targetKey = FirmIDNormalization.normalize("\(type).\(id)")
        return BundledKnowledge.allSources.contains { entityKey(for: $0.path) == targetKey }
    }
}
