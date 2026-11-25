import EiginSDK
import Foundation
import os.lock
import SwiftData

/// Serial host adapter for immutable SDK workspaces and SwiftData persistence.
@Observable
final class DefaultKnowledgeService: KnowledgeService, @unchecked Sendable {
    typealias SDK = EiginSDK.Experimental.Knowledge

    @ObservationIgnored let stateLock = NSRecursiveLock()
    var built = false
    var isBuilt: Bool {
        stateLock.withLock { built }
    }

    var snapshot: SDK.Workspace?
    var session: SDK.Workspace {
        get throws {
            guard let snapshot else { throw KnowledgeServiceError.notBuilt }
            return snapshot
        }
    }

    @ObservationIgnored let persist: @Sendable (ModelContext) throws -> Void
    var activeSpaceID: UUID?
    var activeAgentID: UUID?
    var activeAccessPolicy: SpaceAccessPolicy?
    let modelContainer: ModelContainer

    /// Debounce and source-cache state; model field access is serialized by the service lock.
    struct SharedState: @unchecked Sendable {
        var recentAccess: [String: Date] = [:]
        /// Active-scope metadata snapshot, invalidated on every source save.
        var visibleSourcesCache: [FirmSource]?
    }

    let sharedState = OSAllocatedUnfairLock(initialState: SharedState())

    /// Invalidates graph and metadata after host-owned bulk source changes.
    func invalidateVisibleSourcesCache() {
        stateLock.lock()
        defer { stateLock.unlock() }
        built = false
        clearVisibleSourcesCache()
    }

    func clearVisibleSourcesCache() {
        stateLock.lock()
        defer { stateLock.unlock() }
        sharedState.withLock { $0.visibleSourcesCache = nil }
    }

    /// Coalesces repeat accesses within a typical agent turn.
    let accessDebounceWindow: TimeInterval = 90

    init(
        modelContainer: ModelContainer, initialAccessPolicy: SpaceAccessPolicy? = nil,
        persist: @escaping @Sendable (ModelContext) throws -> Void = { try $0.save() }
    ) {
        self.modelContainer = modelContainer
        self.persist = persist
        activeAccessPolicy = initialAccessPolicy
    }

    func save(_ context: ModelContext) throws {
        stateLock.lock()
        defer { stateLock.unlock() }
        do { try persist(context) }
        catch {
            context.rollback()
            throw error
        }
    }

    func buildWorkspace(_ sources: [FirmSource]) throws -> SDK.Workspace {
        stateLock.lock()
        defer { stateLock.unlock() }
        return try SDK
            .Workspace(sources: bundledSources + sources.map(KnowledgeSDKConversion.source))
    }

    var bundledSources: [SDK.Source] {
        BundledKnowledge.allSources.map {
            .init(id: "bundled:\($0.path)", path: $0.path, content: $0.content, readOnly: true)
        }
    }

    /// Resolves legacy source paths to normalized graph identities.
    func entityKey(for path: String) -> String {
        stateLock.lock()
        defer { stateLock.unlock() }
        return SDK.entityKey(path: path)
    }

    /// Authorizes sources, then selects the most-specific row for each normalized entity.
    func visibleSources(
        from sources: [FirmSource],
        spaceID: UUID?,
        agentID: UUID?,
        accessPolicy: SpaceAccessPolicy?
    ) -> [FirmSource] {
        stateLock.lock()
        defer { stateLock.unlock() }
        let visible = sources.filter { source in
            let spaceMatch: Bool = if let accessPolicy {
                accessPolicy.canAccess(itemSpaceID: source.spaceID)
            } else {
                source.spaceID == nil || source.spaceID == spaceID
            }
            let agentMatch = source.agentID == nil || source.agentID == agentID
            return spaceMatch && agentMatch
        }

        let winners = Set(SDK.selectSourceIDs(
            visible.map { source in
                .init(
                    sourceId: source.id.uuidString,
                    path: source.path,
                    spaceId: source.spaceID?.uuidString,
                    agentId: source.agentID?.uuidString
                )
            }, spaceID: spaceID?.uuidString, agentID: agentID?.uuidString
        ))
        return visible.filter { winners.contains($0.id.uuidString) }
    }

    /// Build the graph if not already built, or rebuild if the scope changed.
    func ensureBuilt(spaceID: UUID?, agentID: UUID?) throws {
        stateLock.lock()
        defer { stateLock.unlock() }
        if isBuilt, activeSpaceID == spaceID, activeAgentID == agentID { return }
        let policy = activeAccessPolicy.map {
            SpaceAccessPolicy(currentSpaceID: spaceID, publicSpaceIDs: $0.publicSpaceIDs)
        }
        try rebuild(spaceID: spaceID, agentID: agentID, accessPolicy: policy)
    }

    /// Reload all sources and rebuild the graph for the given space/agent scope.
    /// Loads global sources (spaceID/agentID == nil) + sources for the given space/agent.
    func rebuild(
        spaceID: UUID?,
        agentID: UUID?,
        accessPolicy: SpaceAccessPolicy? = nil
    ) throws {
        stateLock.lock()
        defer { stateLock.unlock() }

        built = false
        clearVisibleSourcesCache()
        if let accessPolicy { activeAccessPolicy = accessPolicy }
        let spaceLabel = spaceID.map { String($0.uuidString.prefix(8)) } ?? "nil"
        let agentLabel = agentID.map { String($0.uuidString.prefix(8)) } ?? "nil"
        AppLogger.debug(
            "KnowledgeService.rebuild scope=(space:\(public: spaceLabel), agent:\(public: agentLabel))",
            category: .general
        )

        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        let userSources = try context.fetch(
            FetchDescriptor<FirmSource>(sortBy: [SortDescriptor(\.createdAt)])
        )

        AppLogger.debug(
            "KnowledgeService.rebuild total FirmSource records: \(public: userSources.count)",
            category: .general
        )

        // Bind visibility to the requested scope while retaining known public spaces.
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

        activeAccessPolicy = effectivePolicy
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

        // Publish only a successfully built snapshot.
        do {
            snapshot = try buildWorkspace(deduped)
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
        built = true
        clearVisibleSourcesCache()
        AppLogger.debug("KnowledgeService.rebuild succeeded", category: .general)

        backfillEmbeddings(sources: deduped, context: context)
    }

    /// Compute and store embeddings for any visible FirmSource records that lack them.
    func backfillEmbeddings(sources: [FirmSource], context: ModelContext) {
        stateLock.lock()
        defer { stateLock.unlock() }
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
            try? save(context)
            AppLogger.debug(
                "KnowledgeService: backfilled \(public: backfilled) embeddings",
                category: .general
            )
        }
    }

    /// Extract entity type from a source path (e.g. "knowledge/actor/daniel.firm" → "actor").
    func entityType(from path: String) -> String {
        stateLock.lock()
        defer { stateLock.unlock() }
        var stripped = path
            .replacingOccurrences(of: BundledKnowledge.knowledgePrefix, with: "")
            .replacingOccurrences(of: BundledKnowledge.bundledPrefix, with: "")
        if stripped.hasSuffix(".firm") { stripped = String(stripped.dropLast(5)) }
        let parts = stripped.split(separator: "/", maxSplits: 1)
        return parts.count >= 1 ? String(parts[0]) : ""
    }

    /// Extract short entity ID from a source path (e.g. "knowledge/actor/daniel.firm" → "daniel").
    func entityID(from path: String) -> String {
        stateLock.lock()
        defer { stateLock.unlock() }
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
}
