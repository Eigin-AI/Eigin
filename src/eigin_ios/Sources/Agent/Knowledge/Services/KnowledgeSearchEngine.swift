import EiginSDK
import Foundation

/// Ranks knowledge entries for search, hints, and suggested links.
enum KnowledgeSearchEngine {
    typealias SDK = EiginSDK.Experimental.Knowledge

    /// A matching knowledge entry with its rank and source chat.
    struct ScoredEntity: Sendable {
        let entity: FirmEntity
        /// Entry ID including its type, such as `actor.user`.
        let qualifiedID: String
        /// Sort priority; higher values appear first.
        let score: Double
        /// Match strength used to decide whether to include the entry.
        let relevance: Double
        /// Chat where the entry was created, if known.
        let chatID: UUID?
    }

    // MARK: - Primary APIs

    /// Scores visible entries using a query vector and optional keywords.
    /// Results are unsorted; callers apply thresholds and limits.
    /// Pass `keywordNeedle: nil` for meaning-only matching.
    static func score(
        queryEmbedding: [Double],
        keywordNeedle: String? = nil,
        typeFilter: String? = nil,
        includeExpired: Bool = false,
        knowledgeService: any KnowledgeService,
        spaceID: UUID?,
        agentID: UUID?
    ) async throws -> [ScoredEntity] {
        let sourceByPath = try await buildSourceByPath(
            knowledgeService: knowledgeService,
            spaceID: spaceID,
            agentID: agentID
        )

        let schemaNames: [String] = if let typeFilter {
            [typeFilter]
        } else {
            try await knowledgeService.listSchemas(
                spaceID: spaceID, agentID: agentID
            )
        }

        let now = Date().timeIntervalSince1970
        var candidates: [SDK.SearchCandidate] = []
        for schemaName in schemaNames {
            let entities = try await fetchEntities(
                schemaName: schemaName, includeExpired: includeExpired,
                knowledgeService: knowledgeService, spaceID: spaceID, agentID: agentID
            )
            for entity in entities {
                let path = BundledKnowledge.entityPath(
                    prefix: BundledKnowledge.knowledgePrefix, type: schemaName,
                    id: knowledgeShortID(from: entity.id, type: schemaName)
                )
                let memory = sourceByPath[path].map { source in
                    SDK.Memory(
                        sourceId: source.id.uuidString, embedding: source.embedding ?? [],
                        accessCount: source.accessCount,
                        lastAccessedAt: source.lastAccessedAt?.timeIntervalSince1970,
                        importance: source.importance, expired: source.expired,
                        chatId: source.chatID?.uuidString
                    )
                }
                candidates.append(.init(
                    entity: entity,
                    memory: memory
                ))
            }
        }
        return SDK.score(
            candidates, queryEmbedding: queryEmbedding, keywordNeedle: keywordNeedle,
            includeExpired: includeExpired, now: now
        ).map(KnowledgeSDKConversion.scoredEntity)
    }

    /// Embeds a query and returns ranked entries within the threshold and limit.
    static func search(
        query: String,
        typeFilter: String? = nil,
        includeExpired: Bool = false,
        threshold: Double = 0,
        limit: Int? = nil,
        knowledgeService: any KnowledgeService,
        spaceID: UUID?,
        agentID: UUID?
    ) async throws -> [ScoredEntity] {
        let queryEmbedding = EmbeddingHelpers.embed(query) ?? []

        let scored = try await score(
            queryEmbedding: queryEmbedding,
            keywordNeedle: query,
            typeFilter: typeFilter,
            includeExpired: includeExpired,
            knowledgeService: knowledgeService,
            spaceID: spaceID,
            agentID: agentID
        )

        return rank(scored, threshold: threshold, limit: limit)
    }

    // MARK: - Internal helpers

    private static func buildSourceByPath(
        knowledgeService: any KnowledgeService,
        spaceID: UUID?,
        agentID: UUID?
    ) async throws -> [String: FirmSource] {
        let visibleSources = try await knowledgeService.allVisibleSources(
            spaceID: spaceID, agentID: agentID
        )
        return Dictionary(
            visibleSources.map { ($0.path, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private static func fetchEntities(
        schemaName: String,
        includeExpired: Bool,
        knowledgeService: any KnowledgeService,
        spaceID: UUID?,
        agentID: UUID?
    ) async throws -> [FirmEntity] {
        if includeExpired {
            let entityIDs = try await knowledgeService.listEntities(
                type: schemaName, spaceID: spaceID, agentID: agentID
            )
            var fetched: [FirmEntity] = []
            fetched.reserveCapacity(entityIDs.count)
            for entityID in entityIDs {
                if let entity = try await knowledgeService.getEntity(
                    type: schemaName, id: entityID,
                    spaceID: spaceID, agentID: agentID
                ) {
                    fetched.append(entity)
                }
            }
            return fetched
        } else {
            return try await knowledgeService.unexpiredEntities(
                type: schemaName, spaceID: spaceID, agentID: agentID
            )
        }
    }

    /// Clamp adjustments inside disjoint relevance bands even when memory weights change.
    static func rankingScore(relevance: Double, adjustment: Double) -> Double {
        SDK.rankingScore(relevance: relevance, adjustment: adjustment)
    }

    /// Applies SDK thresholds, deterministic ordering, and limits to host results.
    static func rank(
        _ results: [ScoredEntity],
        threshold: Double = 0,
        limit: Int? = nil
    ) -> [ScoredEntity] {
        SDK.rank(
            results.map(KnowledgeSDKConversion.searchResult), threshold: threshold,
            limit: limit.map { UInt64(max(0, $0)) }
        ).map(KnowledgeSDKConversion.scoredEntity)
    }
}
