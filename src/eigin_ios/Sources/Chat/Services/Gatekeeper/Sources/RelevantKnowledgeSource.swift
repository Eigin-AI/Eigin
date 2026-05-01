import Foundation

/// Surfaces a tight set of already-known knowledge entries related to the
/// user's latest message, as a confident starting point for the agent.
///
/// Owns its own ``KnowledgeService`` dependency and does its own fetching
/// via ``KnowledgeHydrator`` inside ``render(_:)``. The pipeline stays
/// dumb — adding this source does not require changes to
/// ``MessagePipeline`` or ``SystemHintInput`` beyond the existing
/// ``SystemHintInput/spaceID`` field.
///
/// **Retention**: entries that matched on a previous turn are kept in view
/// for up to ``maxStaleTurns`` additional turns even if the user's follow-up
/// messages don't re-mention them. This prevents the agent from "forgetting"
/// what the conversation is about when the user says things like "yes, tell
/// me more" or "what about his hobbies?". Fresh matches always rank above
/// stale ones so current-turn signals take priority.
///
/// Skipped when the latest turn has no user message (tool-loop continuation).
/// In small-context mode, renders a minimal format: max 2 entries, truncated
/// summaries, no relationships or preamble.
@MainActor
final class RelevantKnowledgeSource: SystemHintSource {
    let title = "Related knowledge"

    /// Signature for the hydration hook. Injectable so tests can stub it
    /// without running real embedding + scoring.
    typealias Hydrator =
        @Sendable (
            _ userText: String,
            _ knowledgeService: any KnowledgeService,
            _ spaceID: UUID?,
            _ agentID: UUID?
        ) async -> [RelevantKnowledgeEntry]

    private let knowledgeService: any KnowledgeService
    private let hydrator: Hydrator

    /// Maximum turns an entry survives without being re-mentioned.
    /// Current turn counts as 0; the entry stays for `maxStaleTurns`
    /// additional turns before eviction.
    private let maxStaleTurns: Int

    /// Session-scoped retention state. Entries from previous turns are
    /// kept here with a staleness counter that increments each turn
    /// they're not freshly hydrated.
    private var retained: [String: RetainedEntry] = [:]

    private struct RetainedEntry {
        let entry: RelevantKnowledgeEntry
        var staleTurns: Int
    }

    init(
        knowledgeService: any KnowledgeService,
        maxStaleTurns: Int = 2,
        hydrator: @escaping Hydrator = { userText, service, spaceID, agentID in
            await KnowledgeHydrator.hydrate(
                userText: userText,
                knowledgeService: service,
                spaceID: spaceID,
                agentID: agentID
            )
        }
    ) {
        self.knowledgeService = knowledgeService
        self.maxStaleTurns = maxStaleTurns
        self.hydrator = hydrator
    }

    func render(_ input: SystemHintInput) async -> String? {
        let lastUserText = input.messages
            .last(where: { $0.role == "user" })?
            .content ?? ""
        guard !lastUserText.isEmpty else { return nil }

        // Hydrate fresh entries for this turn.
        let freshEntries = await hydrator(
            lastUserText,
            knowledgeService,
            input.spaceID,
            input.agentID
        )

        // Merge fresh entries into retained state (refresh staleness).
        let freshIDs = Set(freshEntries.map(\.qualifiedID))
        for entry in freshEntries {
            retained[entry.qualifiedID] = RetainedEntry(
                entry: entry, staleTurns: 0
            )
        }

        // Age entries that weren't freshly hydrated this turn; evict
        // any that have been stale for too long.
        for id in Array(retained.keys) where !freshIDs.contains(id) {
            retained[id]!.staleTurns += 1
            if retained[id]!.staleTurns > maxStaleTurns {
                retained.removeValue(forKey: id)
            }
        }

        guard !retained.isEmpty else { return nil }

        // Render top N from retained. Fresh entries (staleTurns 0) rank
        // before stale ones; within the same staleness tier, higher
        // scores rank first.
        let maxEntries = input.isSmallContext ? 2 : KnowledgeHydrator.maxEntries
        let toRender = retained.values
            .sorted { a, b in
                if a.staleTurns != b.staleTurns {
                    return a.staleTurns < b.staleTurns
                }
                return a.entry.score > b.entry.score
            }
            .prefix(maxEntries)
            .map(\.entry)

        guard !toRender.isEmpty else { return nil }

        // Small context: minimal — just ID and a short summary, no preamble.
        if input.isSmallContext {
            return toRender.map { entry in
                let summary = entry.summary.count > 60
                    ? String(entry.summary.prefix(60)) + "…"
                    : entry.summary
                return "- \(entry.qualifiedID): \(summary)"
            }.joined(separator: "\n")
        }

        var lines: [String] = []
        lines.append(
            "Things you already know that may relate to what the user just said. "
                + "Use these as a starting point — use search_knowledge or get_knowledge "
                + "for full details or related context if useful."
        )
        lines.append("")

        for entry in toRender {
            lines.append("- **\(entry.qualifiedID)** — \(entry.summary)")
            if !entry.topRelationships.isEmpty {
                var related = "  - Related: "
                    + entry.topRelationships.joined(separator: ", ")
                if entry.moreRelationships > 0 {
                    related += " (+\(entry.moreRelationships) more)"
                }
                lines.append(related)
            }
        }

        return lines.joined(separator: "\n")
    }
}
