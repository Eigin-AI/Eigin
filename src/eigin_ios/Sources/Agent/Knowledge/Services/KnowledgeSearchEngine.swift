import Foundation

/// Shared scoring primitive for knowledge entity ranking.
///
/// Consolidates the inner "scan every visible entity, score it against a
/// query, filter and rank" loop that used to live duplicated across
/// ``SearchKnowledgeTool``, ``KnowledgeAutoLinker``, and the link-suggestion
/// helpers. Both a pre-computed-embedding path (for multi-query callers like
/// ``KnowledgeHydrator``) and a single-query convenience wrapper are
/// exposed.
///
/// Scoring is the existing `max(cosineSimilarity, keywordScore)` formula.
/// Call sites that disable the keyword path (by passing `keywordNeedle: nil`)
/// get pure cosine ranking, which preserves behaviour for the auto-linker and
/// link-suggestion helpers.
enum KnowledgeSearchEngine {
    /// One scored entity result with its backing source metadata.
    struct ScoredEntity {
        let entity: FirmEntity
        /// Normalised `type.shortID` form, regardless of whether the
        /// underlying ``FirmEntity/id`` is already qualified.
        let qualifiedID: String
        /// Cue relevance `max(cosine, keyword)` plus memory boosts (recency ×
        /// frequency + importance). Relevance stays primary; boosts reorder
        /// near-ties. See ``MemoryRanking``.
        let score: Double
        /// Chat the underlying entity was created in, if any.
        let chatID: UUID?
    }

    // MARK: - Primary APIs

    /// Scores every visible entity against a pre-computed query embedding.
    ///
    /// Use this when a single caller wants to run multiple queries against
    /// the same candidate set and avoid re-tokenising or re-embedding the
    /// same text twice — for example the NER + full-message passes inside
    /// ``KnowledgeHydrator``.
    ///
    /// Pass `keywordNeedle: nil` (or an empty string) to disable the
    /// keyword-match path and rely purely on cosine similarity. Results are
    /// unsorted and zero-scored entries are dropped; callers apply their own
    /// thresholds and limits.
    @MainActor
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
        let needle: String? = if let n = keywordNeedle?.lowercased(), !n.isEmpty {
            n
        } else {
            nil
        }

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
                let keywordScore: Double = if let needle {
                    entityKeywordScore(entity, needle: needle)
                } else {
                    0
                }

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

                // Cue relevance gates ranking: only cue-matched memories are
                // considered, then reordered by their memory boosts.
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

                let qualifiedID = "\(schemaName).\(shortID)"
                results.append(ScoredEntity(
                    entity: entity,
                    qualifiedID: qualifiedID,
                    score: relevance + boost,
                    chatID: source?.chatID
                ))
            }
        }

        return results
    }

    /// Convenience wrapper: embed the query string once, score, threshold,
    /// sort, and limit.
    ///
    /// Used by ``SearchKnowledgeTool`` and link-suggestion helpers where the
    /// call site only has a query string and wants a ready-to-render list.
    /// The keyword path is always enabled here, matching the behaviour of
    /// the original `searchResult` implementation.
    @MainActor
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
            scored = scored.filter { $0.score >= threshold }
        }
        scored.sort { $0.score > $1.score }
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

    // MARK: - Keyword scoring (lifted from SearchKnowledgeTool)

    /// Fixed score assigned when any text field on an entity matches the
    /// keyword needle. Distinct from embedding scores so the two paths
    /// contribute at a known, stable level to the `max(cosine, keyword)`
    /// formula.
    private static let keywordMatchScore: Double = 0.5

    /// Returns ``keywordMatchScore`` if any text-like field on the entity
    /// matches the needle, else 0.
    private static func entityKeywordScore(_ entity: FirmEntity, needle: String) -> Double {
        if textMatches(entity.id, needle: needle) { return keywordMatchScore }
        for field in entity.fields {
            if fieldValueContains(field.value, needle: needle) { return keywordMatchScore }
        }
        return 0
    }

    private static func fieldValueContains(_ value: FirmFieldValue, needle: String) -> Bool {
        switch value {
        case .string(let v): textMatches(v, needle: needle)
        case .enum(let v): textMatches(v, needle: needle)
        case .entityReference(let id): textMatches(id, needle: needle)
        case .list(let items): items.contains { fieldValueContains($0, needle: needle) }
        default: false
        }
    }

    /// Match if the text contains the needle as a substring, or if any word
    /// shares a common prefix of 4+ characters with the needle.
    private static func textMatches(_ text: String, needle: String) -> Bool {
        let lower = text.lowercased()
        if lower.contains(needle) { return true }

        guard needle.count >= 4 else { return false }
        let words = lower.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        let minPrefix = min(needle.count, 4)
        for word in words {
            let shared = zip(word, needle).prefix { $0 == $1 }.count
            if shared >= minPrefix { return true }
        }
        return false
    }
}
