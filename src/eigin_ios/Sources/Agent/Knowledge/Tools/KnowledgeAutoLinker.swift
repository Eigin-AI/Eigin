import Foundation
import NaturalLanguage

/// Automatically adds `relates_to` links when a new entity is created without
/// any relationships, using high-confidence heuristics (no LLM or network).
///
/// Two strategies:
/// 1. **Name mention matching** — scan entity text for whole-word mentions of
///    existing actor/thing names (+ special "user"/"agent" aliases).
/// 2. **Semantic similarity** — cosine similarity against stored embeddings
///    with a strict 0.6 threshold.
enum KnowledgeAutoLinker {
    /// Maximum auto-links to add.
    static let maxLinks = 3

    /// Minimum cosine similarity for semantic auto-linking.
    static let semanticThreshold: Double = 0.6

    /// Minimum name length for name-mention matching.
    static let minNameLength = 4

    /// Default actor IDs that can be matched by their role name alone
    /// (e.g. the word "user" matches `actor.user`).
    static let defaultActorAliases: [String: String] = [
        "user": BundledKnowledge.userActorID,
        "agent": BundledKnowledge.agentActorID,
    ]

    /// Returns qualified IDs (e.g. `["actor.daniel"]`) to auto-link the new entity to.
    static func autoLinks(
        for entity: FirmEntity,
        knowledgeService: any KnowledgeService,
        spaceID: UUID?,
        agentID: UUID?
    ) async -> [String] {
        var results: [String] = []
        var seen = Set<String>()
        seen.insert(entity.id) // self-exclusion

        // Strategy 1: name mention matching.
        let nameMatches = await nameMentionLinks(
            for: entity, knowledgeService: knowledgeService,
            spaceID: spaceID, agentID: agentID, seen: &seen
        )
        results.append(contentsOf: nameMatches)

        guard results.count < maxLinks else {
            return Array(results.prefix(maxLinks))
        }

        // Strategy 2: semantic similarity.
        let semanticMatches = await semanticLinks(
            for: entity, knowledgeService: knowledgeService,
            spaceID: spaceID, agentID: agentID, seen: &seen,
            limit: maxLinks - results.count
        )
        results.append(contentsOf: semanticMatches)

        return Array(results.prefix(maxLinks))
    }

    // MARK: - Name mention matching

    /// Tokenize entity text and match against actor/thing names.
    static func nameMentionLinks(
        for entity: FirmEntity,
        knowledgeService: any KnowledgeService,
        spaceID: UUID?,
        agentID: UUID?,
        seen: inout Set<String>
    ) async -> [String] {
        let text = KnowledgeEmbedding.embeddingText(for: entity)
        let tokens = tokenize(text)
        guard !tokens.isEmpty else { return [] }

        var results: [String] = []

        // Check default actor aliases ("user" → actor.user, "agent" → actor.agent).
        for (alias, qualifiedID) in defaultActorAliases {
            guard !seen.contains(qualifiedID) else { continue }
            if tokens.contains(alias) {
                // Verify the entity actually exists.
                let parts = qualifiedID.split(separator: ".", maxSplits: 1)
                guard parts.count == 2,
                      let _ = try? await knowledgeService.getEntity(
                          type: String(parts[0]), id: String(parts[1]),
                          spaceID: spaceID, agentID: agentID
                      )
                else { continue }
                results.append(qualifiedID)
                seen.insert(qualifiedID)
            }
        }

        // Match against actor and thing names.
        for type in ["actor", "thing"] {
            guard let ids = try? await knowledgeService.listEntities(
                type: type, spaceID: spaceID, agentID: agentID
            ) else { continue }

            for id in ids {
                let qualifiedID = "\(type).\(id)"
                guard !seen.contains(qualifiedID) else { continue }
                guard let ent = try? await knowledgeService.getEntity(
                    type: type, id: id, spaceID: spaceID, agentID: agentID
                ) else { continue }

                guard let name = stringField(ent, "name"), !name.isEmpty else { continue }

                if nameMatchesTokens(name: name, tokens: tokens) {
                    results.append(qualifiedID)
                    seen.insert(qualifiedID)
                }
            }
        }

        return results
    }

    /// Check if a name (possibly multi-word) matches any token.
    ///
    /// For single-word names: exact whole-word match (case-insensitive), min 4 chars.
    /// For multi-word names: any individual word (4+ chars) matches a token.
    static func nameMatchesTokens(name: String, tokens: Set<String>) -> Bool {
        let words = name.split(separator: " ").map { String($0).lowercased() }

        for word in words {
            guard word.count >= minNameLength else { continue }
            if tokens.contains(word) { return true }
        }

        return false
    }

    /// Extract lowercased word tokens from text using NLTokenizer.
    ///
    /// Strips possessive suffixes (`'s`, `'s`) so "Daniel's" also yields "daniel".
    static func tokenize(_ text: String) -> Set<String> {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text

        var tokens = Set<String>()
        tokenizer.enumerateTokens(in: text.startIndex ..< text.endIndex) { range, _ in
            var word = String(text[range]).lowercased()
            tokens.insert(word)
            // Strip possessive suffix to match base name.
            for suffix in ["'s", "\u{2019}s"] {
                if word.hasSuffix(suffix) {
                    word = String(word.dropLast(suffix.count))
                    if !word.isEmpty { tokens.insert(word) }
                    break
                }
            }
            return true
        }
        return tokens
    }

    // MARK: - Semantic similarity

    /// Find semantically similar entities above the strict threshold.
    static func semanticLinks(
        for entity: FirmEntity,
        knowledgeService: any KnowledgeService,
        spaceID: UUID?,
        agentID: UUID?,
        seen: inout Set<String>,
        limit: Int
    ) async -> [String] {
        guard limit > 0 else { return [] }

        let text = KnowledgeEmbedding.embeddingText(for: entity)
        guard let queryEmbedding = EmbeddingHelpers.embed(text) else { return [] }

        let scored: [KnowledgeSearchEngine.ScoredEntity]
        do {
            scored = try await KnowledgeSearchEngine.score(
                queryEmbedding: queryEmbedding,
                keywordNeedle: nil,
                includeExpired: true,
                knowledgeService: knowledgeService,
                spaceID: spaceID,
                agentID: agentID
            )
        } catch {
            return []
        }

        let filtered = scored
            .filter { $0.score > semanticThreshold && !seen.contains($0.qualifiedID) }
            .sorted { $0.score > $1.score }

        var results: [String] = []
        for item in filtered.prefix(limit) {
            results.append(item.qualifiedID)
            seen.insert(item.qualifiedID)
        }
        return results
    }

    // MARK: - Helpers

    private static func stringField(_ entity: FirmEntity, _ name: String) -> String? {
        guard let field = entity.fields.first(where: { $0.name == name }) else { return nil }
        if case .string(let v) = field.value { return v }
        return nil
    }
}
