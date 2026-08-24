import Foundation

/// A memory flagged for the agent to consider during consolidation.
struct ConsolidationItem {
    let qualifiedID: String
    let type: String
    let summary: String
}

/// The deterministic candidate set for one consolidation run.
struct ConsolidationCandidates {
    /// Groups of near-duplicate / likely-conflicting memories (each size ≥ 2).
    var duplicateClusters: [[ConsolidationItem]] = []
    /// Long-unused, low-stakes memories worth retiring.
    var evictionCandidates: [ConsolidationItem] = []
    /// Every entry surfaced this run (including cluster members trimmed from the
    /// display). Stamped as reviewed so the next run rotates to different work.
    var reviewedIDs: [String] = []

    var isEmpty: Bool {
        duplicateClusters.isEmpty && evictionCandidates.isEmpty
    }

    /// Plain-English list of what to look at this run, injected into the
    /// consolidation prompt. Empty string when there's nothing flagged.
    /// Renders the candidate list only. The how-to (merge/supersede/forget/
    /// contest) lives in the maintenance prompt, so it isn't duplicated here.
    func promptSection() -> String {
        guard !isEmpty else { return "" }
        var lines = ["Here's what stood out in your knowledge this time:"]

        if !duplicateClusters.isEmpty {
            lines.append("")
            lines.append("Related entries worth a review:")
            for (i, cluster) in duplicateClusters.enumerated() {
                lines.append("\(i + 1).")
                for item in cluster {
                    lines.append("   - \(item.qualifiedID): \(item.summary)")
                }
            }
        }

        if !evictionCandidates.isEmpty {
            lines.append("")
            lines.append("Long-unused and low-stakes:")
            for item in evictionCandidates {
                lines.append("- \(item.qualifiedID): \(item.summary)")
            }
        }

        return lines.joined(separator: "\n")
    }
}

/// Deterministic candidate computation for the background consolidation pass.
///
/// Recomputed from current signals each run — nothing is stored between runs, so
/// resolved problems simply aren't re-detected (progress lives in the data). The
/// agent does the judgement; this just decides *what to look at*.
enum MemoryConsolidation {
    /// Cosine at or above which two memories are treated as duplicates/conflicts.
    static let conflictThreshold = KnowledgeConflictHint.threshold

    /// Activation below which a memory is stale enough to consider retiring.
    /// Frequency keeps activation up, so a once-used, long-untouched memory
    /// falls here while a historically well-used one stays protected. Sits
    /// above the accessCount-1 floor (~0.11) and below the freshly-touched
    /// baseline (~0.2), so recent memories are safe.
    static let evictionActivationFloor: Double = 0.15

    /// A memory must have gone untouched at least this long to be an eviction
    /// candidate — a grace period so recently-used (and freshly-migrated)
    /// knowledge is never surfaced.
    static let evictionMinAgeDays: Double = 90

    /// Importance at or above which a memory is never an eviction candidate —
    /// the safety net for rare-but-critical facts.
    static let evictionImportanceCeiling: Double = 0.7

    static let maxClusters = 5
    static let maxEvictions = 10

    /// Cap on members shown per cluster. Union-find chains transitively, so a
    /// dense topic neighborhood can grow huge; we show only the most cohesive
    /// core (the likeliest true duplicates) and let the rest resurface next run.
    static let maxClusterMembers = 8

    /// Compute duplicate clusters and eviction candidates for the scope.
    @MainActor
    static func candidates(
        knowledgeService: any KnowledgeService,
        spaceID: UUID?,
        agentID: UUID?,
        now: Date = Date()
    ) async -> ConsolidationCandidates {
        let sources = await (try? knowledgeService.allVisibleSources(
            spaceID: spaceID, agentID: agentID
        )) ?? []

        // Eligible: live, not already contested, has an embedding, user-owned.
        struct Row { let qid: String; let type: String; let source: FirmSource }
        var rows: [Row] = []
        for source in sources {
            guard !source.expired, !source.contested, source.embedding != nil,
                  !knowledgeService.isBundled(path: source.path),
                  let qid = qualifiedID(fromPath: source.path),
                  let parsed = parseQualifiedKnowledgeID(qid)
            else { continue }
            rows.append(Row(qid: qid, type: parsed.type, source: source))
        }

        let grouped = duplicateClusters(
            rows.map { ($0.qid, $0.type, $0.source.embedding ?? [], $0.source.lastReviewedAt) }
        )
        // Exclude every grouped member from eviction, even ones trimmed from a
        // capped cluster, so a duplicate isn't also offered up as stale.
        let clustered = grouped.groupedIDs

        func activation(_ source: FirmSource) -> Double {
            MemoryRanking.activation(
                accessCount: source.accessCount, lastAccessedAt: source.lastAccessedAt, now: now
            )
        }

        // Eviction: stale + low-stakes, excluding anything already in a cluster.
        // Least-recently-reviewed first (so we rotate), then most stale.
        let evictions = rows
            .filter { row in
                guard !clustered.contains(row.qid) else { return false }
                guard row.source.importance < evictionImportanceCeiling else { return false }
                // Grace period: must be genuinely stale, not just quiet lately.
                guard let last = row.source.lastAccessedAt,
                      now.timeIntervalSince(last) >= evictionMinAgeDays * 86400
                else { return false }
                return activation(row.source) < evictionActivationFloor
            }
            .sorted { a, b in
                let ra = a.source.lastReviewedAt ?? .distantPast
                let rb = b.source.lastReviewedAt ?? .distantPast
                if ra != rb { return ra < rb }
                return activation(a.source) < activation(b.source)
            }
            .prefix(maxEvictions)
            .map { ($0.qid, $0.type) }

        var result = ConsolidationCandidates()
        var reviewed: [String] = []
        for cluster in grouped.clusters.prefix(maxClusters) {
            // Stamp the whole cluster (incl. trimmed members) so the same core
            // doesn't resurface next run just because a peripheral member is new.
            reviewed.append(contentsOf: cluster.map(\.0))
            var items: [ConsolidationItem] = []
            for (qid, type) in cluster.prefix(maxClusterMembers) {
                await items.append(item(
                    qid: qid,
                    type: type,
                    knowledgeService: knowledgeService,
                    spaceID: spaceID,
                    agentID: agentID
                ))
            }
            result.duplicateClusters.append(items)
        }
        for (qid, type) in evictions {
            reviewed.append(qid)
            await result.evictionCandidates.append(item(
                qid: qid, type: type, knowledgeService: knowledgeService,
                spaceID: spaceID, agentID: agentID
            ))
        }
        result.reviewedIDs = reviewed
        return result
    }

    // MARK: - Clustering

    /// Union-find grouping of memories whose embeddings are pairwise similar at
    /// or above ``conflictThreshold``. Returns full clusters (size 2+), members
    /// ordered most-cohesive-first, and the clusters ordered
    /// least-recently-reviewed first (so the pass rotates through the base),
    /// tie-broken by peak similarity then ID for determinism. Also returns the
    /// full set of grouped IDs. Display capping happens in ``candidates``.
    static func duplicateClusters(
        _ entries: [(qid: String, type: String, embedding: [Double], reviewedAt: Date?)]
    ) -> (clusters: [[(String, String)]], groupedIDs: Set<String>) {
        var parent = Array(entries.indices)
        func find(_ x: Int) -> Int {
            var r = x
            while parent[r] != r {
                parent[r] = parent[parent[r]]; r = parent[r]
            }
            return r
        }
        func union(_ a: Int, _ b: Int) {
            parent[find(a)] = find(b)
        }
        func cos(_ a: Int, _ b: Int) -> Double {
            EmbeddingHelpers.cosineSimilarity(entries[a].embedding, entries[b].embedding)
        }

        for i in entries.indices {
            guard !entries[i].embedding.isEmpty else { continue }
            for j in (i + 1) ..< entries.count {
                guard !entries[j].embedding.isEmpty else { continue }
                if cos(i, j) >= conflictThreshold { union(i, j) }
            }
        }

        var groups: [Int: [Int]] = [:]
        for i in entries.indices where !entries[i].embedding.isEmpty {
            groups[find(i), default: []].append(i)
        }

        var groupedIDs: Set<String> = []
        var ranked: [(members: [Int], peak: Double, reviewed: Date)] = []
        for members in groups.values where members.count >= 2 {
            for m in members {
                groupedIDs.insert(entries[m].qid)
            }

            // Peak pairwise similarity ranks confidence.
            var peak = 0.0
            for x in 0 ..< members.count {
                for y in (x + 1) ..< members.count {
                    peak = max(peak, cos(members[x], members[y]))
                }
            }

            // Order members most-cohesive-first so display capping keeps the core.
            let ordered: [Int] = members.count <= 2 ? members : members
                .map { m -> (idx: Int, avg: Double) in
                    let others = members.filter { $0 != m }
                    let avg = others.reduce(0.0) { $0 + cos(m, $1) } / Double(others.count)
                    return (m, avg)
                }
                .sorted { $0.avg != $1.avg
                    ? $0.avg > $1.avg
                    : entries[$0.idx].qid < entries[$1.idx].qid
                }
                .map(\.idx)

            // A cluster is as "fresh" as its least-recently-reviewed member, so
            // any never-reviewed member keeps the whole cluster in play.
            let reviewed = members.map { entries[$0].reviewedAt ?? .distantPast }.min()
                ?? .distantPast
            ranked.append((ordered, peak, reviewed))
        }

        // Least-recently-reviewed first (rotation); tie-break peak desc then
        // smallest ID so the ordering is stable run to run.
        ranked.sort { lhs, rhs in
            if lhs.reviewed != rhs.reviewed { return lhs.reviewed < rhs.reviewed }
            if lhs.peak != rhs.peak { return lhs.peak > rhs.peak }
            let lMin = lhs.members.map { entries[$0].qid }.min() ?? ""
            let rMin = rhs.members.map { entries[$0].qid }.min() ?? ""
            return lMin < rMin
        }

        let clusters = ranked.map { $0.members.map { (entries[$0].qid, entries[$0].type) } }
        return (clusters, groupedIDs)
    }

    // MARK: - Helpers

    @MainActor
    private static func item(
        qid: String, type: String,
        knowledgeService: any KnowledgeService, spaceID: UUID?, agentID: UUID?
    ) async -> ConsolidationItem {
        let shortID = knowledgeShortID(from: qid, type: type)
        let summary: String = if let entity = try? await knowledgeService.getEntity(
            type: type, id: shortID, spaceID: spaceID, agentID: agentID
        ) {
            knowledgeSummary(for: entity)
        } else {
            qid
        }
        return ConsolidationItem(qualifiedID: qid, type: type, summary: summary)
    }

    /// Parse `"{type}.{id}"` from a source path (`{prefix}/{type}/{id}.firm`).
    static func qualifiedID(fromPath path: String) -> String? {
        var stripped = path
            .replacingOccurrences(of: BundledKnowledge.knowledgePrefix, with: "")
            .replacingOccurrences(of: BundledKnowledge.bundledPrefix, with: "")
        if stripped.hasSuffix(".firm") { stripped = String(stripped.dropLast(5)) }
        let parts = stripped.split(separator: "/", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        let type = String(parts[0])
        var id = String(parts[1])
        if id.hasPrefix("\(type).") { id = String(id.dropFirst(type.count + 1)) }
        return "\(type).\(id)"
    }
}
