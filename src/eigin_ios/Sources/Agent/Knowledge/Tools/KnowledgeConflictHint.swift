import Foundation

/// Live-path conflict detection. When a knowledge entry is saved, scan for
/// existing entries that are near-duplicates or likely contradictions, so the
/// agent can reconcile there and then (supersede / merge / keep).
///
/// A gentle nudge, never a gate: the save has already happened. If nothing is
/// close, or the scan fails, no hint is added. Reuses the same embedding scan as
/// ``KnowledgeAutoLinker`` but at a stricter threshold — auto-linking wants
/// "related" (0.6), conflict wants "so similar it might be the same thing".
enum KnowledgeConflictHint {
    /// Minimum cosine similarity to treat an existing entry as a possible
    /// duplicate or contradiction. Higher than the auto-link threshold.
    static let threshold: Double = 0.85

    /// Most similar entries to surface.
    static let maxHints = 2

    /// Qualified IDs + summaries of existing entries close enough to `entity`
    /// to be worth reconciling. Excludes the entity itself. Empty when nothing
    /// is close.
    @MainActor
    static func similarExisting(
        to entity: FirmEntity,
        knowledgeService: any KnowledgeService,
        spaceID: UUID?,
        agentID: UUID?
    ) async -> [[String: Any]] {
        let text = KnowledgeEmbedding.embeddingText(for: entity)
        guard let queryEmbedding = EmbeddingHelpers.embed(text) else { return [] }
        return await similarExisting(
            queryEmbedding: queryEmbedding,
            excluding: entity.id,
            knowledgeService: knowledgeService,
            spaceID: spaceID,
            agentID: agentID
        )
    }

    /// Core scan against a precomputed query embedding. Separated so it can be
    /// tested deterministically without the embedding model.
    @MainActor
    static func similarExisting(
        queryEmbedding: [Double],
        excluding selfID: String,
        knowledgeService: any KnowledgeService,
        spaceID: UUID?,
        agentID: UUID?
    ) async -> [[String: Any]] {
        let scored: [KnowledgeSearchEngine.ScoredEntity]
        do {
            scored = try await KnowledgeSearchEngine.score(
                queryEmbedding: queryEmbedding,
                keywordNeedle: nil,
                knowledgeService: knowledgeService,
                spaceID: spaceID,
                agentID: agentID
            )
        } catch {
            return []
        }

        return scored
            .filter { $0.qualifiedID != selfID && $0.score > threshold }
            .sorted { $0.score > $1.score }
            .prefix(maxHints)
            .map { ["id": $0.entity.id, "summary": knowledgeSummary(for: $0.entity)] }
    }

    /// A short, action-oriented note pairing with ``similarExisting``.
    static let message = """
    These knowledge entries look similar. If one replaces the other, use \
    supersede_knowledge; if it duplicates one, use merge_knowledge; otherwise \
    ignore this.
    """
}
