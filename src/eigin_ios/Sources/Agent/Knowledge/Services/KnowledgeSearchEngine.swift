import Foundation

/// Ranks knowledge entries for search, hints, and suggested links.
enum KnowledgeSearchEngine {
    /// Keeps memory adjustments within each match tier.
    private static let maximumTierAdjustment = 0.09

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

        let now = Date()
        let lexicalQuery = KnowledgeLexicalMatcher.Query(keywordNeedle ?? "")

        var results: [ScoredEntity] = []

        for schemaName in schemaNames {
            let entities = try await fetchEntities(
                schemaName: schemaName,
                includeExpired: includeExpired,
                knowledgeService: knowledgeService,
                spaceID: spaceID,
                agentID: agentID
            )

            for entity in entities {
                var embeddingScore = 0.0
                let shortID = knowledgeShortID(from: entity.id, type: schemaName)
                let path = BundledKnowledge.entityPath(
                    prefix: BundledKnowledge.knowledgePrefix,
                    type: schemaName,
                    id: shortID
                )
                let source = sourceByPath[path]
                if let embedding = source?.embedding, !queryEmbedding.isEmpty {
                    embeddingScore = EmbeddingHelpers.cosineSimilarity(
                        queryEmbedding, embedding
                    )
                }

                let qualifiedID = "\(schemaName).\(shortID)"
                let keywordScore = KnowledgeLexicalMatcher.score(
                    entity: entity, qualifiedID: qualifiedID, query: lexicalQuery
                )
                let relevance = max(embeddingScore, keywordScore)
                guard relevance > 0 else { continue }

                // Hide expired memories unless explicitly requested.
                if !includeExpired, source?.expired == true { continue }

                let boost: Double = if let source {
                    MemoryRanking.boost(
                        accessCount: source.accessCount,
                        lastAccessedAt: source.lastAccessedAt,
                        importance: source.importance,
                        now: now
                    )
                } else {
                    0
                }

                results.append(ScoredEntity(
                    entity: entity,
                    qualifiedID: qualifiedID,
                    score: rankingScore(relevance: relevance, adjustment: boost),
                    relevance: relevance,
                    chatID: source?.chatID
                ))
            }
        }

        return results
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

        var scored = try await score(
            queryEmbedding: queryEmbedding,
            keywordNeedle: query,
            typeFilter: typeFilter,
            includeExpired: includeExpired,
            knowledgeService: knowledgeService,
            spaceID: spaceID,
            agentID: agentID
        )

        if threshold > 0 {
            scored = scored.filter { $0.relevance >= threshold }
        }
        scored.sort(by: ranksBefore)
        if let limit, scored.count > limit {
            scored = Array(scored.prefix(limit))
        }
        return scored
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
        let weighted = adjustment * min(1, relevance)
        // Adjacent protected tiers are at least 0.2 apart.
        return relevance + min(maximumTierAdjustment, max(-maximumTierAdjustment, weighted))
    }

    /// Stable ordering for identical evidence and memory signals.
    static func ranksBefore(_ lhs: ScoredEntity, _ rhs: ScoredEntity) -> Bool {
        lhs.score == rhs.score ? lhs.qualifiedID < rhs.qualifiedID : lhs.score > rhs.score
    }
}
