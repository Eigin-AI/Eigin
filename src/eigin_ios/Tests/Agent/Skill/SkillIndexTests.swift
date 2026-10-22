@testable import Eigin
import Foundation
import Testing

@Suite("SkillIndex")
struct SkillIndexTests {
    private func skill(
        id: String,
        displayName: String? = nil,
        description: String,
        customDescriptor: String? = nil,
        toolKeys: [String] = []
    ) -> Skill {
        Skill(
            id: id, displayName: displayName ?? id, description: description,
            instruction: "instruction",
            requiredTools: Set(toolKeys.map {
                ToolCapability(
                    kind: .discovered, key: $0, displayName: $0,
                    defaultPermissionLevel: .ask, category: .extensions
                )
            }),
            alwaysActive: false,
            customDescriptor: customDescriptor
        )
    }

    /// Query text matching a skill's descriptor embeds to [1, 0]; matching an
    /// impostor descriptor embeds to [0, 1] (orthogonal, cosine 0).
    private nonisolated func keyedEmbedder(target: String) -> @Sendable (String) -> [Double]? {
        { text in text.contains(target) ? [1.0, 0.0] : [0.0, 1.0] }
    }

    @Test func ranksMatchingSkillFirst() async {
        let index = SkillIndex(embed: keyedEmbedder(target: "recipe"))
        let cooking = skill(id: "cooking", description: "Find a recipe and cook dinner")
        let health = skill(id: "health", description: "Track workouts and sleep")
        let results = await index.search(query: "give me a recipe", among: [health, cooking])

        #expect(results?.first?.skill.id == "cooking")
        #expect((results?.count ?? 0) <= 2)
    }

    @Test func thresholdExcludesWeakMatches() async {
        let index = SkillIndex(embed: keyedEmbedder(target: "recipe"))
        // Health's descriptor keys to the orthogonal vector: cosine 0 < 0.55.
        let health = skill(id: "health", description: "Track workouts and sleep")
        let results = await index.search(query: "recipe", among: [health])
        #expect(results?.isEmpty == true)
    }

    @Test func limitCapsResults() async {
        let index = SkillIndex(embed: { _ in [1.0] })
        let skills = (0 ..< 6).map { skill(id: "s\($0)", description: "match \($0)") }
        let results = await index.search(query: "match", among: skills, limit: 3)
        #expect(results?.count == 3)
    }

    @Test func unavailableEmbedderReturnsNil() async {
        let index = SkillIndex(embed: { _ in nil })
        let results = await index.search(
            query: "anything",
            among: [skill(id: "s", description: "d")]
        )
        #expect(results == nil)
    }

    @Test func descriptorEmbeddingsAreCachedAcrossSearches() async {
        let counter = LockedCounter()
        let skillIDs: Set = ["a", "b"]
        let index = SkillIndex { text in
            // Descriptors are the skill's id; the query is the literal "query".
            if text == "query" {
                counter.incrementQuery()
            } else if skillIDs.contains(text) {
                counter.incrementDescriptor()
            }
            return [1.0]
        }
        let skills = [skill(id: "a", description: "a"), skill(id: "b", description: "b")]
        _ = await index.search(query: "query", among: skills)
        _ = await index.search(query: "query", among: skills)
        #expect(counter.descriptors == 2) // once per skill, cached after
        #expect(counter.queries == 2) // every search embeds the query
    }

    @Test func descriptorFallsBackToDescription() {
        let withOverride = skill(id: "a", description: "plain", customDescriptor: "authored")
        let without = skill(id: "b", description: "plain")
        #expect(withOverride.descriptor == "authored")
        #expect(without.descriptor == "plain")
    }

    @Test func partWiseSearchScoresBestSentence() async {
        // Query = three message "parts"; only the cooking part matches the
        // cooking descriptor. Max-over-parts hints cooking; a single blurry
        // blob of the whole turn might not clear the threshold at all.
        let index = SkillIndex { text in
            if text.contains("hvad skal vi have") { return [1.0, 0.0, 0.0] }
            if text.contains("noise") || text.contains("small talk") { return [0.0, 1.0, 0.0] }
            return [0.0, 0.0, 1.0]
        }
        let cooking = skill(id: "cooking", description: "hvad skal vi have til aftensmad")
        let health = skill(id: "health", description: "completely unrelated text here")
        let results = await index.search(
            queryParts: [
                "small talk about the weather",
                "hvad skal vi have til aftensmad",
                "and more noise",
            ],
            among: [health, cooking]
        )
        #expect(results?.first?.skill.id == "cooking")
        #expect(results?.count == 1)
    }

    @Test func partWiseSearchReturnsNilWhenEveryPartFailsToEmbed() async {
        let index = SkillIndex(embed: { _ in nil })
        let results = await index.search(
            queryParts: ["", "  "],
            among: [skill(id: "a", description: "d")]
        )
        #expect(results == nil)
    }

    @Test func emptyCandidatesReturnEmptyResults() async {
        let index = SkillIndex(embed: { _ in [1.0] })
        let results = await index.search(query: "anything", among: [])
        #expect(results?.isEmpty == true)
    }

    @Test func emptyQueryPartsReturnNil() async {
        let index = SkillIndex(embed: { _ in [1.0] })
        let results = await index.search(queryParts: [], among: [skill(id: "a", description: "d")])
        #expect(results == nil)
    }

    // MARK: - Lexical matching (#317)

    @Test func exactNameMatchSurfacesWhenSemanticsMiss() async {
        // Query "GitLab" is semantically orthogonal to the descriptor, but
        // the name matches exactly — like #317's instruction-less GitLab MCP
        // server, sparse metadata must not hide a named skill.
        let index = SkillIndex { text in
            text.contains("repositories") ? [1.0, 0.0] : [0.0, 1.0]
        }
        let gitlab = skill(
            id: "mcp__gitlab",
            displayName: "GitLab",
            description: "manage repositories"
        )
        let results = await index.search(query: "GitLab", among: [gitlab])
        #expect(results?.first?.skill.id == "mcp__gitlab")
    }

    @Test func exactNameMatchOutranksStrongSemanticMatch() async {
        // The decoy scores 0.9 semantically against the [0, 1] query vector;
        // GitLab scores 0 semantically but 1.0 on exact name — identity beats
        // similarity.
        let index = SkillIndex { text in
            if text.contains("aqua") { return [0.4359, 0.9] }
            if text.contains("repositories") { return [1.0, 0.0] }
            return [0.0, 1.0]
        }
        let decoy = skill(id: "aqua", displayName: "Aqua", description: "aqua everywhere")
        let gitlab = skill(
            id: "mcp__gitlab",
            displayName: "GitLab",
            description: "manage repositories"
        )
        let results = await index.search(query: "GitLab", among: [decoy, gitlab])
        #expect(results?.first?.skill.id == "mcp__gitlab")
        #expect(results?.count == 2)
    }

    @Test func namePrefixMatchSurfacesShortNameQueries() async {
        // "git" prefix-matches "gitlab" — at 0.6 it even clears the hint
        // threshold, but weak evidence cannot mask the semantic floor.
        let index = SkillIndex { text in
            text.contains("deceased") ? [1.0, 0.0] : [0.0, 1.0]
        }
        let gitlab = skill(
            id: "mcp__gitlab",
            displayName: "GitLab",
            description: "deceased metadata"
        )
        let results = await index.search(query: "git", among: [gitlab])
        #expect(results?.first?.skill.id == "mcp__gitlab")
    }

    @Test func interiorSubstringsDoNotMatch() async {
        let index = SkillIndex { $0.count > 10 ? [1.0, 0.0] : [0.0, 1.0] }
        let gitlab = skill(
            id: "mcp__gitlab",
            displayName: "GitLab",
            description: "deceased metadata"
        )
        let results = await index.search(query: "bla", among: [gitlab])
        #expect(results?.isEmpty == true)
    }

    @Test func idTokenizationMatchesItsOwnName() async {
        // Querying a skill's raw ID ("mcp__gitlab") matches the identity
        // phrase after separator normalization.
        let index = SkillIndex { _ in [0.9, 0.4359] }
        let gitlab = skill(
            id: "mcp__gitlab",
            displayName: "GitLab",
            description: "manage repositories"
        )
        let results = await index.search(query: "mcp__gitlab", among: [gitlab])
        #expect(results?.first?.skill.id == "mcp__gitlab")
    }

    @Test func toolWordsMatchAcrossSeparators() async {
        // "merge request" matches create_merge_request's words — the tool
        // name is searchable even though the descriptor hides it.
        let index = SkillIndex { $0.count > 12 ? [1.0, 0.0] : [0.0, 1.0] }
        let gitlab = skill(
            id: "mcp__gitlab", displayName: "GitLab", description: "dead weight",
            toolKeys: [MCPNaming.toolName(serverName: "GitLab", toolName: "create_merge_request")]
        )
        let results = await index.search(
            query: "open a merge request",
            among: [gitlab],
            threshold: SkillIndex.searchThreshold
        )
        #expect(results?.first?.skill.id == "mcp__gitlab")
    }

    @Test func mcpMarkerSearchesButStaysBelowHintThreshold() async {
        // The identity's "mcp" token is body-tier: search finds it (0.5 >=
        // 0.3), hints don't (0.5 < 0.55).
        let index = SkillIndex { text in
            text.contains("manage") ? [1.0, 0.0] : [0.0, 1.0]
        }
        let gitlab = skill(
            id: "mcp__gitlab",
            displayName: "GitLab",
            description: "manage repositories"
        )
        let search = await index.search(
            query: "MCP",
            among: [gitlab],
            threshold: SkillIndex.searchThreshold
        )
        #expect(search?.first?.skill.id == "mcp__gitlab")
        #expect((search?.first?.score ?? 1) < SkillIndex.matchThreshold) // search-only tier
        let hints = await index.search(query: "MCP", among: [gitlab])
        #expect(hints?.isEmpty == true)
    }

    @Test func toolNamesAreSearchableBeyondTheDescriptorCap() async {
        // The projected descriptor is truncated at 500 characters; tool names
        // stay searchable through requiredTools either way.
        let index = SkillIndex { $0.count > 14 ? [1.0, 0.0] : [0.0, 1.0] }
        let gitlab = skill(
            id: "mcp__gitlab", displayName: "GitLab",
            description: "long instructions crowd out the tool list",
            customDescriptor: "…",
            toolKeys: [MCPNaming.toolName(serverName: "GitLab", toolName: "delete_release_webhook")]
        )
        let results = await index.search(
            query: "delete release webhook",
            among: [gitlab],
            threshold: SkillIndex.searchThreshold
        )
        #expect(results?.first?.skill.id == "mcp__gitlab")
    }

    @Test func moreToolsDoNotInflateLexicalScores() async {
        // Scores are per-skill maxima: five tool mentions can't outweigh one.
        let index = SkillIndex { text in
            text.contains("deceased") ? [1.0, 0.0] : [0.0, 1.0]
        }
        let one = skill(
            id: "mcp__a", displayName: "One", description: "deceased metadata",
            toolKeys: [MCPNaming.toolName(serverName: "One", toolName: "create_merge_request")]
        )
        let five = skill(
            id: "mcp__b", displayName: "Five", description: "deceased metadata",
            toolKeys: [
                MCPNaming.toolName(serverName: "Five", toolName: "create_merge_request"),
                MCPNaming.toolName(serverName: "Five", toolName: "list_pipelines"),
                MCPNaming.toolName(serverName: "Five", toolName: "delete_release_webhook"),
                MCPNaming.toolName(serverName: "Five", toolName: "close_merge_request"),
                MCPNaming.toolName(serverName: "Five", toolName: "open_merge_request"),
            ]
        )
        let results = await index.search(
            query: "merge request", among: [five, one], threshold: SkillIndex.searchThreshold
        )
        #expect(results?.count == 2)
        #expect(results?[0].score == results?[1].score)
    }

    @Test func exactNameMatchSurvivesUnavailableEmbedder() async {
        // Without the embedder, exact identity is still trustworthy (#317's
        // device may lack the model assets entirely).
        let index = SkillIndex(embed: { _ in nil })
        let gitlab = skill(
            id: "mcp__gitlab",
            displayName: "GitLab",
            description: "manage repositories"
        )
        let results = await index.search(query: "GitLab", among: [gitlab])
        #expect(results?.first?.skill.id == "mcp__gitlab")
    }

    @Test func weakLexicalEvidenceDoesNotRescueUnavailableEmbedder() async {
        // Prefix/tool-word matches without a semantic check are too risky to
        // present — report unavailable (nil), not a speculative match.
        let index = SkillIndex(embed: { _ in nil })
        let gitlab = skill(
            id: "mcp__gitlab", displayName: "GitLab", description: "deceased metadata",
            toolKeys: [MCPNaming.toolName(serverName: "GitLab", toolName: "create_merge_request")]
        )
        let results = await index.search(
            query: "merge request", among: [gitlab], threshold: SkillIndex.searchThreshold
        )
        #expect(results == nil)
    }

    @Test func largeCatalogNamedSkillStillSurfaces() async {
        // A big synthetic MCP catalog stays functional: same query, same
        // winner — proving the scan is linear catalog work, not per-tool
        // combinatorics. No wall-clock asserting.
        let index = SkillIndex { text in
            text.contains("metadata") ? [1.0, 0.0] : [0.0, 1.0]
        }
        let skills = (0 ..< 500).map { i in
            skill(
                id: "mcp__i\(i)", displayName: "Server \(i)", description: "deceased metadata \(i)",
                toolKeys: [
                    MCPNaming.toolName(serverName: "Server \(i)", toolName: "create_thing\(i)"),
                    MCPNaming.toolName(serverName: "Server \(i)", toolName: "list_things"),
                ]
            )
        }
        let gitlab = skill(
            id: "mcp__gitlab",
            displayName: "GitLab",
            description: "manage repositories"
        )

        let results = await index.search(query: "GitLab", among: skills + [gitlab])
        #expect(results?.first?.skill.id == "mcp__gitlab")
        #expect(results?.count == 1) // 500 tangential servers stay below threshold
    }
}

/// Thread-safe counters for @Sendable embed closures in tests.
private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var descriptorEmbeds = 0
    private var queryEmbeds = 0

    var descriptors: Int {
        lock.lock()
        defer { lock.unlock() }
        return descriptorEmbeds
    }

    var queries: Int {
        lock.lock()
        defer { lock.unlock() }
        return queryEmbeds
    }

    func incrementDescriptor() {
        lock.lock()
        descriptorEmbeds += 1
        lock.unlock()
    }

    func incrementQuery() {
        lock.lock()
        queryEmbeds += 1
        lock.unlock()
    }
}
