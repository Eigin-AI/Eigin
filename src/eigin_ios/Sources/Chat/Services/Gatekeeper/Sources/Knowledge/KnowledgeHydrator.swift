import Foundation

/// Snapshot of one knowledge entry selected for per-turn hydration.
///
/// Produced by ``KnowledgeHydrator`` and consumed by
/// ``RelevantKnowledgeSource`` for markdown formatting. Pre-formatted so the
/// source can render without touching FFI types.
struct RelevantKnowledgeEntry {
    /// Normalised `type.shortID` form, e.g. `"actor.mette"`.
    let qualifiedID: String
    /// The underlying entity type (`"actor"`, `"thing"`, `"fact"`, etc.).
    let type: String
    /// Short primary-field text (name, claim, content) truncated to a
    /// reasonable length — see ``knowledgeSummary(for:maxLength:)``.
    let summary: String
    /// `max(cosine, keyword)` score from ``KnowledgeSearchEngine``.
    let score: Double
    /// Up to ``KnowledgeHydrator/maxRelationshipsPerEntry`` qualified IDs.
    let topRelationships: [String]
    /// How many more edges exist beyond ``topRelationships``.
    let moreRelationships: Int
}

/// Per-turn knowledge hydration: scores the knowledge base against the
/// latest user message with a two-pass strategy (token-level name mention
/// against entity text + whole-message semantic similarity), merges and
/// ranks the top N matches, and snapshots each match with its top
/// relationships.
///
/// This is a *nudge* for the agent — conservatively shown only when the
/// match is confident. Below-threshold turns produce an empty result and the
/// ``RelevantKnowledgeSource`` stays silent.
///
/// All errors are swallowed and logged; an empty result is the safe fallback
/// at every step so a degraded knowledge service never blocks a turn.
@MainActor
enum KnowledgeHydrator {
    /// Maximum entries surfaced in the hint block.
    static let maxEntries: Int = 3

    /// Maximum relationships shown per entry (the `(+N more)` indicator
    /// handles anything beyond this).
    static let maxRelationshipsPerEntry: Int = 3

    /// Minimum trimmed character count to attempt hydration.
    static let minMessageChars: Int = 15

    /// Minimum word count to attempt hydration.
    static let minMessageWords: Int = 3

    /// Entity types the name-mention pass scans.
    ///
    /// Includes `actor`, `thing`, and `fact` — the types with meaningful
    /// name/claim text a user might reference. The overlap-ratio scoring
    /// naturally handles the difference: a 1-token actor name scores 1.0
    /// on any mention, while a 5-token fact claim needs multiple matching
    /// tokens to rank high. `output` and `note` are excluded because
    /// their free-form content would produce too many accidental overlaps.
    ///
    /// Future optimisation: pre-tokenise entity surfaces at rebuild time,
    /// or build a reverse token → entities index.
    static let nameMentionTypes: [String] = ["actor", "thing", "fact"]

    /// Bagatelle threshold for the KB search pass. Filters the weakest
    /// embedding noise while staying low enough to admit keyword matches
    /// (which score 0.5) and moderate semantic hits. The top-3 selection
    /// is the real precision filter.
    static let searchMinScore: Double = 0.35

    /// Returns the top-N hydration entries for `userText`, or `[]` if the
    /// message is too trivial, the knowledge base has nothing above
    /// threshold, or the service is unavailable.
    static func hydrate(
        userText: String,
        knowledgeService: any KnowledgeService,
        spaceID: UUID?,
        agentID: UUID?
    ) async -> [RelevantKnowledgeEntry] {
        let trimmed = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isSubstantive(trimmed) else { return [] }

        // Accumulator keyed by qualifiedID; keep the max score on collision
        // so entities hit by multiple passes rank by their strongest signal.
        var bestScored: [String: KnowledgeSearchEngine.ScoredEntity] = [:]

        // Pass 1: token name-mention for actors + things.
        //
        // Tokenises the user message and checks each actor/thing entity's
        // name tokens for overlap. Case-insensitive, language-agnostic,
        // and doesn't rely on capitalisation — "bob", "Bob", and "BOB"
        // all match. Catches coined names like "Eigin" that NLTagger
        // wouldn't recognise. Score is `overlap / entityTokens` so a
        // single-token actor name scores 1.0 on a mention.
        let mentionResults = await findByNameMention(
            userText: trimmed,
            knowledgeService: knowledgeService,
            spaceID: spaceID,
            agentID: agentID
        )
        merge(mentionResults, into: &bestScored)

        // Pass 2: full KB search (keyword + embedding hybrid).
        //
        // Runs the user message through the same hybrid search the
        // agent's `search_knowledge` tool uses — `max(cosine, keyword)`
        // across all entity types. Catches semantic topic matches,
        // substring hits, and fuzzy-prefix matches that the per-token
        // name-mention pass misses. Word-averaged embeddings can produce
        // moderate scores for unrelated content, but the top-3 ranking
        // naturally pushes noise below stronger name-mention hits, and
        // in the absence of strong matches a moderate semantic hit is
        // still useful context for the agent.
        do {
            let searchResults = try await KnowledgeSearchEngine.search(
                query: trimmed,
                threshold: searchMinScore,
                limit: 10,
                knowledgeService: knowledgeService,
                spaceID: spaceID,
                agentID: agentID
            )
            merge(searchResults, into: &bestScored)
        } catch {
            AppLogger.warning(
                "KnowledgeHydrator: KB search pass failed: \(public: error.localizedDescription)",
                category: .chat
            )
        }

        guard !bestScored.isEmpty else { return [] }

        let topScored = bestScored
            .values
            .sorted { $0.score > $1.score }
            .prefix(maxEntries)

        var results: [RelevantKnowledgeEntry] = []
        results.reserveCapacity(topScored.count)
        for scored in topScored {
            let entry = await buildEntry(
                from: scored,
                knowledgeService: knowledgeService,
                spaceID: spaceID,
                agentID: agentID
            )
            results.append(entry)
        }
        return results
    }

    // MARK: - Name-mention pass

    /// Finds actors and things whose name tokens overlap with the user's
    /// message tokens. Score is `overlap / entityTokens` — a single-token
    /// name like "Bob" scores 1.0 on any mention.
    ///
    /// Case-insensitive, language-agnostic. Tokens shorter than
    /// ``MessageTokenizer/defaultMinTokenLength`` are dropped on both sides.
    static func findByNameMention(
        userText: String,
        knowledgeService: any KnowledgeService,
        spaceID: UUID?,
        agentID: UUID?
    ) async -> [KnowledgeSearchEngine.ScoredEntity] {
        let messageTokens = tokenizeForMention(userText)
        guard !messageTokens.isEmpty else { return [] }

        var results: [KnowledgeSearchEngine.ScoredEntity] = []
        let now = Date()

        for schemaName in nameMentionTypes {
            let entities: [FirmEntity]
            do {
                entities = try await knowledgeService.validEntities(
                    type: schemaName,
                    spaceID: spaceID, agentID: agentID,
                    at: now
                )
            } catch {
                // Missing schema or scoped-out type — silently skip.
                continue
            }

            for entity in entities {
                let entityTokens = tokenizeEntitySurface(entity, type: schemaName)
                guard !entityTokens.isEmpty else { continue }
                let overlap = entityTokens.intersection(messageTokens).count
                guard overlap > 0 else { continue }

                let ratio = Double(overlap) / Double(entityTokens.count)

                let shortID = knowledgeShortID(from: entity.id, type: schemaName)
                let qualifiedID = "\(schemaName).\(shortID)"
                results.append(
                    KnowledgeSearchEngine.ScoredEntity(
                        entity: entity,
                        qualifiedID: qualifiedID,
                        score: ratio,
                        chatID: nil
                    )
                )
            }
        }

        return results
    }

    // MARK: - Tokenisation

    /// Tokenises free-form text for the name-mention pass: lowercased,
    /// length-filtered, letters-only (filters out numbers and punctuation
    /// artefacts). Language-agnostic via ``NLTokenizer``.
    nonisolated static func tokenizeForMention(_ text: String) -> Set<String> {
        MessageTokenizer.tokenize(text)
    }

    /// Tokenises an entity's user-facing text surface (short id plus the
    /// `name`, `claim`, and `content` fields) for the name-mention pass.
    private nonisolated static func tokenizeEntitySurface(
        _ entity: FirmEntity, type: String
    ) -> Set<String> {
        var combined = knowledgeShortID(from: entity.id, type: type)
        for field in entity.fields {
            guard field.name == "name" || field.name == "claim" || field.name == "content" else {
                continue
            }
            if case .string(let value) = field.value {
                combined += " " + value
            }
        }
        // Entity ids often use underscores or hyphens as separators —
        // normalise them to spaces so ``NLTokenizer`` splits on them.
        combined = combined.replacingOccurrences(of: "_", with: " ")
        combined = combined.replacingOccurrences(of: "-", with: " ")
        return tokenizeForMention(combined)
    }

    // MARK: - Other helpers

    /// True when `text` has enough signal to justify a hydration pass.
    private static func isSubstantive(_ text: String) -> Bool {
        guard text.count >= minMessageChars else { return false }
        let words = text.split(whereSeparator: { $0.isWhitespace })
        return words.count >= minMessageWords
    }

    /// Merges `incoming` into `accumulator`, keeping the highest score when
    /// the same qualified ID appears in both.
    private static func merge(
        _ incoming: [KnowledgeSearchEngine.ScoredEntity],
        into accumulator: inout [String: KnowledgeSearchEngine.ScoredEntity]
    ) {
        for scored in incoming {
            if let existing = accumulator[scored.qualifiedID] {
                if scored.score > existing.score {
                    accumulator[scored.qualifiedID] = scored
                }
            } else {
                accumulator[scored.qualifiedID] = scored
            }
        }
    }

    /// Builds a ``RelevantKnowledgeEntry`` for one scored entity, hydrating
    /// its top relationships from the knowledge service.
    private static func buildEntry(
        from scored: KnowledgeSearchEngine.ScoredEntity,
        knowledgeService: any KnowledgeService,
        spaceID: UUID?,
        agentID: UUID?
    ) async -> RelevantKnowledgeEntry {
        let type = scored.entity.entityType
        let shortID = knowledgeShortID(from: scored.entity.id, type: type)
        let summary = knowledgeSummary(for: scored.entity)

        let related = await fetchRelated(
            type: type,
            id: shortID,
            selfQualifiedID: scored.qualifiedID,
            knowledgeService: knowledgeService,
            spaceID: spaceID,
            agentID: agentID
        )

        let topRelationships = Array(related.prefix(maxRelationshipsPerEntry))
        let moreRelationships = max(0, related.count - topRelationships.count)

        return RelevantKnowledgeEntry(
            qualifiedID: scored.qualifiedID,
            type: type,
            summary: summary,
            score: scored.score,
            topRelationships: topRelationships,
            moreRelationships: moreRelationships
        )
    }

    /// Fetches outgoing + incoming relationships for an entity, dedupes,
    /// drops self-references, and returns the deduped qualified ID list.
    ///
    /// Errors are swallowed and logged — a hydration entry with no related
    /// edges still renders.
    private static func fetchRelated(
        type: String,
        id: String,
        selfQualifiedID: String,
        knowledgeService: any KnowledgeService,
        spaceID: UUID?,
        agentID: UUID?
    ) async -> [String] {
        var related: [FirmEntity] = []
        do {
            let outgoing = try await knowledgeService.getRelated(
                type: type, id: id, direction: .outgoing,
                spaceID: spaceID, agentID: agentID
            )
            related.append(contentsOf: outgoing)
        } catch {
            AppLogger.warning(
                "KnowledgeHydrator: outgoing related fetch failed for \(public: selfQualifiedID): \(public: error.localizedDescription)",
                category: .chat
            )
        }
        do {
            let incoming = try await knowledgeService.getRelated(
                type: type, id: id, direction: .incoming,
                spaceID: spaceID, agentID: agentID
            )
            related.append(contentsOf: incoming)
        } catch {
            AppLogger.warning(
                "KnowledgeHydrator: incoming related fetch failed for \(public: selfQualifiedID): \(public: error.localizedDescription)",
                category: .chat
            )
        }

        var seen = Set<String>()
        var ordered: [String] = []
        for entity in related {
            let qualified = entity.id.contains(".") ? entity.id : "\(entity.entityType).\(entity.id)"
            guard qualified != selfQualifiedID else { continue }
            if seen.insert(qualified).inserted {
                ordered.append(qualified)
            }
        }
        return ordered
    }
}
