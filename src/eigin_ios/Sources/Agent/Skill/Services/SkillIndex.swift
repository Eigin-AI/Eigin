import Foundation

/// A skill scored against a retrieval query.
struct ScoredSkill: Sendable {
    let skill: Skill
    let score: Double
}

/// Retrieval over skill descriptors: ranks candidates by a combination of
/// exact lexical evidence (name, ID, tool words — ``SkillLexicalMatcher``)
/// and embedding cosine, and returns the best matches.
///
/// Returns `nil` when the embedder is unavailable (model assets missing) and
/// no exact name match anchors the query — callers treat that as "search
/// unavailable", not a no-match. Empty array means retrieval ran and nothing
/// scored above `threshold`.
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
    /// individual sentences of the last few messages. Each part is embedded
    /// and scored separately; a skill's score is its best-matching part,
    /// never lower than its best lexical match (name, ID, tool words).
    ///
    /// Lexical evidence weaker than exact name/ID only counts for skills that
    /// also have an embedding vector — an embedder-less device must surface
    /// only certain identity matches, not prefix or tool-word guesses.
    nonisolated func search(
        queryParts: [String],
        among candidates: [Skill],
        threshold: Double = SkillIndex.matchThreshold,
        limit: Int = SkillIndex.resultLimit
    ) async -> [ScoredSkill]? {
        let parts = queryParts.filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }

        let embeddedParts = await embeddedParts(parts)
        let descriptorVectors = await embeddings(for: candidates)
        let lexical = await lexicalScores(for: candidates, queryParts: parts)

        let scored = candidates.compactMap { skill -> ScoredSkill? in
            let descriptorVector = descriptorVectors[skill.id]
            let semantic = descriptorVector.map { vector in
                embeddedParts
                    .map { EmbeddingHelpers.cosineSimilarity($0, vector) }
                    .max() ?? 0
            } ?? 0
            // Prefix and tool-word evidence needs an embedded query and a
            // semantic vector to corroborate it; exact identity stands alone
            // (see #317).
            let lexicalScore = lexical[skill.id].map { match in
                match.isExactName || (!embeddedParts.isEmpty && descriptorVector != nil)
                    ? match.score : 0
            } ?? 0
            let score = max(semantic, lexicalScore)
            guard score >= threshold else { return nil }
            return ScoredSkill(skill: skill, score: score)
        }
        .sorted { $0.score == $1.score ? $0.skill.id < $1.skill.id : $0.score > $1.score }

        // Embedder produced nothing (down or asset-less) and no descriptor
        // embedded: only exact identity matches surfaced, so anything else
        // is "unavailable" — don't report a no-match the search never
        // established.
        if embeddedParts.isEmpty, descriptorVectors.isEmpty {
            return scored.isEmpty ? nil : Array(scored.prefix(limit))
        }

        return Array(scored.prefix(limit))
    }

    /// Embeds the query parts, skipping parts the embedder can't handle.
    private func embeddedParts(_ parts: [String]) -> [[Double]] {
        parts.compactMap(embed)
    }

    /// Lexical evidence per skill: exact/prefix token matches over display
    /// name, ID, tool names, and descriptor tokens. Pure token work, so it
    /// always runs on this actor — never on the main thread.
    private func lexicalScores(
        for candidates: [Skill],
        queryParts: [String]
    ) -> [String: (score: Double, isExactName: Bool)] {
        let tokenizedParts = queryParts.map(SkillLexicalMatcher.tokens).filter { !$0.isEmpty }
        guard !tokenizedParts.isEmpty else { return [:] }
        var result: [String: (score: Double, isExactName: Bool)] = [:]
        for skill in candidates {
            let fields = SkillLexicalMatcher.fields(for: skill)
            if let match = SkillLexicalMatcher.score(fields: fields, queryParts: tokenizedParts) {
                result[skill.id] = match
            }
        }
        return result
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
