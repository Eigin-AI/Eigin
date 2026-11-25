import EiginSDKBindings

public extension EiginSDK.Experimental {
    /// Experimental source-backed knowledge; hosts own authorization and persistence.
    enum Knowledge {
        public typealias Workspace = KnowledgeWorkspace
        public typealias Source = KnowledgeSource
        public typealias Entity = KnowledgeEntity
        public typealias Field = KnowledgeField
        public typealias FieldValue = KnowledgeFieldValue
        public typealias Schema = KnowledgeSchema
        public typealias SchemaField = KnowledgeSchemaField
        public typealias Direction = KnowledgeDirection
        public typealias QueryResult = KnowledgeQueryResult
        public typealias Failure = KnowledgeError
        public typealias Memory = KnowledgeMemory
        public typealias SearchCandidate = KnowledgeSearchCandidate
        public typealias SearchResult = KnowledgeSearchResult
        public typealias SourceScope = KnowledgeSourceScope

        /// Selects text for the host's embedding provider.
        public static func embeddingText(_ entity: Entity) -> String {
            knowledgeEmbeddingText(entity: entity)
        }

        /// Scores an authorized candidate set without generating embeddings.
        public static func score(_ candidates: [SearchCandidate], queryEmbedding: [Double], keywordNeedle: String?, includeExpired: Bool, now: Double) -> [SearchResult] {
            knowledgeScoreCandidates(candidates: candidates, queryEmbedding: queryEmbedding, keywordNeedle: keywordNeedle, includeExpired: includeExpired, now: now)
        }

        /// Applies relevance thresholds, deterministic ordering, and an optional limit.
        public static func rank(_ results: [SearchResult], threshold: Double, limit: UInt64?) -> [SearchResult] {
            knowledgeRankResults(results: results, threshold: threshold, limit: limit)
        }

        /// Selects shadow winners from host-authorized sources, preserving input order.
        public static func selectSourceIDs(_ sources: [SourceScope], spaceID: String?, agentID: String?) -> [String] {
            knowledgeSelectSourceIds(sources: sources, spaceId: spaceID, agentId: agentID)
        }

        /// Resolves legacy paths to normalized entity keys.
        public static func entityKey(path: String) -> String {
            knowledgeEntityKey(path: path)
        }

        /// Scores lexical evidence separately from host embeddings.
        public static func lexicalScore(entity: Entity, qualifiedID: String, query: String) -> Double {
            knowledgeLexicalScore(entity: entity, qualifiedId: qualifiedID, query: query)
        }

        /// Bounds memory adjustments within relevance bands.
        public static func rankingScore(relevance: Double, adjustment: Double) -> Double {
            knowledgeRankingScore(relevance: relevance, adjustment: adjustment)
        }

        /// Computes recency-decayed memory activation from Unix timestamps.
        public static func memoryActivation(accessCount: Double, lastAccessedAt: Double?, now: Double) -> Double {
            knowledgeMemoryActivation(accessCount: accessCount, lastAccessedAt: lastAccessedAt, now: now)
        }

        /// Maps importance around its neutral value of 0.5.
        public static func importanceLift(_ importance: Double) -> Double {
            knowledgeImportanceLift(importance: importance)
        }

        /// Computes the portable memory ranking adjustment.
        public static func memoryBoost(accessCount: Double, lastAccessedAt: Double?, importance: Double, now: Double) -> Double {
            knowledgeMemoryBoost(accessCount: accessCount, lastAccessedAt: lastAccessedAt, importance: importance, now: now)
        }
    }
}
