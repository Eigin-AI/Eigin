import Foundation

/// A skill scored against a retrieval query.
struct ScoredSkill: Sendable {
    let skill: Skill
    let score: Double
}

/// Retrieval over skill descriptors: scores candidates against a query and
/// returns the best matches.
///
/// Returns `nil` when the embedder is unavailable (model assets missing), an
/// empty array when nothing scored above `threshold`.
protocol SkillIndexing: Actor {
    func search(
        query: String,
        among candidates: [Skill],
        threshold: Double,
        limit: Int
    ) async -> [ScoredSkill]?

    func search(
        queryParts: [String],
        among candidates: [Skill],
        threshold: Double,
        limit: Int
    ) async -> [ScoredSkill]?
}

/// Semantic retrieval over the skill catalog.
///
/// Embeds each candidate skill's ``Skill/descriptor`` lazily, once, and caches
/// the vector — keyed by descriptor *text*, so MCP skills whose server
/// instructions refresh re-embed instead of going stale. Embedding a short
/// descriptor is ms-scale. Matching is brute-force cosine (via
/// ``EmbeddingHelpers/cosineSimilarity``) over the candidates; fine at catalog
/// scale (≤ hundreds). Query side: embed the caller's text parts (e.g. the
/// sentences of recent messages) and rank.
///
/// No persistence, no vector index. Embedding runs off the main thread;
/// callers simply `await`.
actor SkillIndex: SkillIndexing {
    private let embed: @Sendable (String) -> [Double]?
    /// Descriptor text → vector. Keyed by text, not skill ID, so refreshed
    /// MCP metadata re-embeds.
    private var cache: [String: [Double]] = [:]

    init(
        embed: @escaping @Sendable (String) -> [Double]? = {
            ContextualEmbedder().embed($0)
        }
    ) {
        self.embed = embed
    }

    /// Ranks `candidates` against `query`, best first, capped at `limit`.
    ///
    /// Candidates should already be filtered (on-demand, not-active,
    /// capability-satisfied — see ``SkillCatalog/activatable``).
    nonisolated func search(
        query: String,
        among candidates: [Skill],
        threshold: Double = SkillIndex.matchThreshold,
        limit: Int = SkillIndex.resultLimit
    ) async -> [ScoredSkill]? {
        await search(queryParts: [query], among: candidates, threshold: threshold, limit: limit)
    }

    /// Ranks `candidates` against a *decomposition* of the query — e.g. the
    /// individual sentences of the last few messages. Each part is embedded and
    /// scored separately; a skill's score is its best-matching part.
    nonisolated func search(
        queryParts: [String],
        among candidates: [Skill],
        threshold: Double = SkillIndex.matchThreshold,
        limit: Int = SkillIndex.resultLimit
    ) async -> [ScoredSkill]? {
        let parts = queryParts.filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }

        let embeddedParts = await embeddedParts(parts)
        guard !embeddedParts.isEmpty else { return nil }

        let descriptorVectors = await embeddings(for: candidates)

        let scored = candidates.compactMap { skill -> ScoredSkill? in
            guard let descriptorVector = descriptorVectors[skill.id] else { return nil }
            // A skill's score is its best-matching part.
            let score = embeddedParts
                .map { EmbeddingHelpers.cosineSimilarity($0, descriptorVector) }
                .max() ?? 0
            return score >= threshold ? ScoredSkill(skill: skill, score: score) : nil
        }
        .sorted { $0.score > $1.score }

        return Array(scored.prefix(limit))
    }

    /// Embeds the query parts, skipping parts the embedder can't handle.
    private func embeddedParts(_ parts: [String]) -> [[Double]] {
        parts.compactMap(embed)
    }

    /// The descriptor vector per candidate, embedding and caching on first use.
    private func embeddings(for skills: [Skill]) -> [String: [Double]] {
        var result: [String: [Double]] = [:]
        for skill in skills {
            if let cached = cache[skill.descriptor] {
                result[skill.id] = cached
                continue
            }
            guard let vector = embed(skill.descriptor) else { continue }
            cache[skill.descriptor] = vector
            result[skill.id] = vector
        }
        // MCP metadata can change across a session; bound the cache so
        // churned descriptors don't accumulate forever.
        if cache.count > Self.cacheLimit {
            cache.removeAll()
        }
        return result
    }

    /// Cache bound, so churned MCP descriptors don't accumulate forever.
    nonisolated static let cacheLimit = 512

    /// Minimum cosine similarity to count as a match.
    nonisolated static let matchThreshold = 0.55

    /// Search results use a lower floor — recall over precision, the agent
    /// evaluates the matches itself.
    nonisolated static let searchThreshold = 0.3

    /// Maximum skills returned by a search or hint pass.
    nonisolated static let resultLimit = 4
}
