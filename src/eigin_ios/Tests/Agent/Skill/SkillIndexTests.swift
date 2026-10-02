@testable import Eigin
import Foundation
import Testing

@Suite("SkillIndex")
struct SkillIndexTests {
    private func skill(id: String, description: String, customDescriptor: String? = nil) -> Skill {
        Skill(
            id: id, displayName: id, description: description,
            instruction: "instruction", requiredTools: [], alwaysActive: false,
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
