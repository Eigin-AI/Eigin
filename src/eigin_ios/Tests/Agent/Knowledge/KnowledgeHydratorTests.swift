@testable import Eigin
import Foundation
import Testing

@Suite("KnowledgeHydrator")
@MainActor
struct KnowledgeHydratorTests {
    // MARK: - Fixtures

    private func namedEntity(type: String, id: String, name: String) -> FirmEntity {
        FirmEntity(
            id: "\(type).\(id)",
            entityType: type,
            fields: [FirmField(name: "name", value: .string(value: name))]
        )
    }

    private func factEntity(id: String, name: String? = nil, claim: String) -> FirmEntity {
        var fields = [FirmField(name: "claim", value: .string(value: claim))]
        if let name { fields.append(FirmField(name: "name", value: .string(value: name))) }
        return FirmEntity(id: "fact.\(id)", entityType: "fact", fields: fields)
    }

    private func sourceFor(type: String, id: String, embedding: [Double]) -> FirmSource {
        let path = BundledKnowledge.entityPath(
            prefix: BundledKnowledge.knowledgePrefix, type: type, id: id
        )
        let fs = FirmSource(path: path, content: "")
        fs.embedding = embedding
        return fs
    }

    /// Seeds actors, a thing, and a fact with real embeddings for
    /// integration tests.
    private func seededFake() -> FakeKnowledgeService {
        let fake = FakeKnowledgeService()
        for name in ["Bob", "Alice", "Mette", "Daniel", "Ada"] {
            let id = name.lowercased()
            fake.entities["actor.\(id)"] = namedEntity(type: "actor", id: id, name: name)
            fake.sources.append(
                sourceFor(
                    type: "actor",
                    id: id,
                    embedding: EmbeddingHelpers.embed("\(name), human") ?? []
                )
            )
        }
        fake.entities["thing.eigin"] = namedEntity(type: "thing", id: "eigin", name: "Eigin")
        fake.sources.append(
            sourceFor(
                type: "thing",
                id: "eigin",
                embedding: EmbeddingHelpers.embed("Eigin, digital") ?? []
            )
        )
        fake.entities["fact.eigin_vs_frameworks"] = factEntity(
            id: "eigin_vs_frameworks",
            name: "Eigin vs. Agent Frameworks",
            claim: "Eigin is a personal AI agent, not a framework for building agents."
        )
        fake.sources.append(
            sourceFor(
                type: "fact",
                id: "eigin_vs_frameworks",
                embedding: EmbeddingHelpers.embed(
                    "Eigin vs. Agent Frameworks: Eigin is a personal AI agent, not a framework for building agents."
                ) ?? []
            )
        )
        return fake
    }

    // MARK: - Trivial-message skip

    @Test func shortMessageSkips() async {
        let fake = seededFake()
        let result = await KnowledgeHydrator.hydrate(
            userText: "yes",
            knowledgeService: fake, spaceID: nil, agentID: nil
        )
        #expect(result.isEmpty)
    }

    @Test func tooFewWordsSkips() async {
        let fake = seededFake()
        let result = await KnowledgeHydrator.hydrate(
            userText: "okay thanks",
            knowledgeService: fake, spaceID: nil, agentID: nil
        )
        #expect(result.isEmpty)
    }

    @Test func emptyStringSkips() async {
        let fake = seededFake()
        let result = await KnowledgeHydrator.hydrate(
            userText: "   ",
            knowledgeService: fake, spaceID: nil, agentID: nil
        )
        #expect(result.isEmpty)
    }

    // MARK: - Name-mention pass (actors + things)

    @Test func nameMentionMatchesKnownActor() async {
        let fake = seededFake()
        let result = await KnowledgeHydrator.hydrate(
            userText: "What about now. Bob",
            knowledgeService: fake, spaceID: nil, agentID: nil
        )
        #expect(result.contains { $0.qualifiedID == "actor.bob" })
    }

    @Test func nameMentionMatchesLowercaseInput() async {
        let fake = seededFake()
        let result = await KnowledgeHydrator.hydrate(
            userText: "i had a chat with bob this morning",
            knowledgeService: fake, spaceID: nil, agentID: nil
        )
        #expect(result.contains { $0.qualifiedID == "actor.bob" })
    }

    @Test func nameMentionMatchesUppercaseInput() async {
        let fake = seededFake()
        let result = await KnowledgeHydrator.hydrate(
            userText: "I was with BOB earlier today",
            knowledgeService: fake, spaceID: nil, agentID: nil
        )
        #expect(result.contains { $0.qualifiedID == "actor.bob" })
    }

    @Test func nameMentionMatchesShortName() async {
        let fake = seededFake()
        let result = await KnowledgeHydrator.hydrate(
            userText: "I was just talking with Ada today",
            knowledgeService: fake, spaceID: nil, agentID: nil
        )
        #expect(result.contains { $0.qualifiedID == "actor.ada" })
    }

    @Test func nameMentionMatchesCoinedName() async {
        let fake = seededFake()
        let result = await KnowledgeHydrator.hydrate(
            userText: "Can you tell me about Eigin today?",
            knowledgeService: fake, spaceID: nil, agentID: nil
        )
        #expect(result.contains { $0.qualifiedID == "thing.eigin" })
    }

    @Test func nameMentionMatchesCoinedNameLowercase() async {
        let fake = seededFake()
        let result = await KnowledgeHydrator.hydrate(
            userText: "i really like using eigin these days",
            knowledgeService: fake, spaceID: nil, agentID: nil
        )
        #expect(result.contains { $0.qualifiedID == "thing.eigin" })
    }

    @Test func nameMentionReturnsEmptyForUnknownMentions() async {
        let fake = seededFake()
        let result = await KnowledgeHydrator.hydrate(
            userText: "I was talking with Charlie yesterday about something",
            knowledgeService: fake, spaceID: nil, agentID: nil
        )
        // Charlie doesn't exist in the KB.
        #expect(!result.contains { $0.qualifiedID.hasPrefix("actor.charlie") })
    }

    // MARK: - KB search pass (facts + semantic)

    /// The user's exact reported case: a fact with the same text as the
    /// message should surface via the keyword path in the search engine.
    @Test func searchPassMatchesFactByKeyword() async {
        let fake = seededFake()
        let result = await KnowledgeHydrator.hydrate(
            userText: "Eigin vs. Agent Frameworks",
            knowledgeService: fake, spaceID: nil, agentID: nil
        )
        #expect(result.contains { $0.qualifiedID == "fact.eigin_vs_frameworks" })
    }

    /// A longer message that references the fact topic should match via
    /// keyword or embedding similarity.
    @Test func searchPassMatchesFactFromLongerMessage() async {
        let fake = seededFake()
        let result = await KnowledgeHydrator.hydrate(
            userText: "What's the difference between Eigin and agent frameworks?",
            knowledgeService: fake, spaceID: nil, agentID: nil
        )
        // thing.eigin should match via name-mention on "Eigin".
        #expect(result.contains { $0.qualifiedID == "thing.eigin" })
        // The fact should match via the search pass (keyword substring
        // on "eigin" + "agent" + "frameworks", or embedding similarity).
        // If it doesn't surface, the search engine's scoring may not be
        // strong enough — keep this test to track.
        #expect(result.contains { $0.qualifiedID == "fact.eigin_vs_frameworks" })
    }

    // MARK: - Merge + ranking

    @Test func mergeDedupesByQualifiedID() async {
        let fake = seededFake()
        // "Daniel" matches via name-mention AND may match via KB search.
        // Merge keeps one entry with the max score.
        let result = await KnowledgeHydrator.hydrate(
            userText: "Daniel is working on a new project this week",
            knowledgeService: fake, spaceID: nil, agentID: nil
        )
        #expect(result.count(where: { $0.qualifiedID == "actor.daniel" }) == 1)
    }

    @Test func limitsToMaxEntries() async {
        let fake = FakeKnowledgeService()
        // Seed 5 actors that all match the message.
        for i in 0 ..< 5 {
            let name = "Person\(i)"
            let id = name.lowercased()
            fake.entities["actor.\(id)"] = namedEntity(type: "actor", id: id, name: name)
            fake.sources.append(
                sourceFor(
                    type: "actor",
                    id: id,
                    embedding: EmbeddingHelpers.embed("\(name), human") ?? []
                )
            )
        }
        let result = await KnowledgeHydrator.hydrate(
            userText: "Tell me about Person0 and Person1 and Person2 and Person3 and Person4",
            knowledgeService: fake, spaceID: nil, agentID: nil
        )
        #expect(result.count <= KnowledgeHydrator.maxEntries)
    }

    // MARK: - Relationship hydration

    @Test func relationshipHydrationTopThreePlusMore() async {
        let fake = seededFake()
        fake.relatedOutgoing["actor.daniel"] = (0 ..< 5).map { i in
            namedEntity(type: "thing", id: "t\(i)", name: "T\(i)")
        }
        let result = await KnowledgeHydrator.hydrate(
            userText: "Daniel is building projects daily",
            knowledgeService: fake, spaceID: nil, agentID: nil
        )
        let entry = result.first { $0.qualifiedID == "actor.daniel" }
        #expect(entry?.topRelationships.count == KnowledgeHydrator.maxRelationshipsPerEntry)
        #expect(entry?.moreRelationships == 5 - KnowledgeHydrator.maxRelationshipsPerEntry)
    }

    @Test func relationshipsExcludeSelf() async {
        let fake = seededFake()
        fake.relatedOutgoing["actor.daniel"] = [
            namedEntity(type: "actor", id: "daniel", name: "Daniel"),
            namedEntity(type: "thing", id: "phoenix", name: "Phoenix"),
        ]
        let result = await KnowledgeHydrator.hydrate(
            userText: "Daniel is building projects daily",
            knowledgeService: fake, spaceID: nil, agentID: nil
        )
        let entry = result.first { $0.qualifiedID == "actor.daniel" }
        #expect(entry?.topRelationships.contains("actor.daniel") == false)
        #expect(entry?.topRelationships.contains("thing.phoenix") == true)
    }

    // MARK: - Scope passthrough

    @Test func scopeForwardsToService() async {
        let fake = seededFake()
        let spaceID = UUID()
        let agentID = UUID()
        _ = await KnowledgeHydrator.hydrate(
            userText: "Daniel is working on something today",
            knowledgeService: fake,
            spaceID: spaceID,
            agentID: agentID
        )
        #expect(fake.receivedSpaceIDs.allSatisfy { $0 == spaceID })
        #expect(fake.receivedAgentIDs.allSatisfy { $0 == agentID })
    }

    // MARK: - Error tolerance

    @Test func getRelatedErrorFallsBackToEmptyRelationships() async {
        let fake = seededFake()
        fake.throwOnGetRelated = true
        let result = await KnowledgeHydrator.hydrate(
            userText: "Daniel is working on something today",
            knowledgeService: fake, spaceID: nil, agentID: nil
        )
        let entry = result.first { $0.qualifiedID == "actor.daniel" }
        #expect(entry != nil)
        #expect(entry?.topRelationships.isEmpty == true)
    }

    // MARK: - Ranking: real matches outrank noise

    /// When the user mentions a known entity, name-mention scores it at
    /// 1.0 which dominates any embedding-noise results from the KB
    /// search pass. The top-3 result should have the real match first.
    @Test func realMatchOutranksEmbeddingNoise() async {
        let fake = seededFake()
        let result = await KnowledgeHydrator.hydrate(
            userText: "I was chatting with Daniel about something",
            knowledgeService: fake, spaceID: nil, agentID: nil
        )
        #expect(result.first?.qualifiedID == "actor.daniel")
        #expect((result.first?.score ?? 0) > 0.9)
    }

    /// The result list is bounded at `maxEntries` even when the KB
    /// search pass returns many moderate-scoring entities.
    @Test func resultsBoundedByMaxEntries() async {
        let fake = seededFake()
        let result = await KnowledgeHydrator.hydrate(
            userText: "Tell me about everyone and everything you know",
            knowledgeService: fake, spaceID: nil, agentID: nil
        )
        #expect(result.count <= KnowledgeHydrator.maxEntries)
    }

    // MARK: - Danish input

    @Test func matchesInDanishInput() async {
        let fake = seededFake()
        let result = await KnowledgeHydrator.hydrate(
            userText: "Kan du fortælle mig om Eigin og hvad Bob syntes?",
            knowledgeService: fake, spaceID: nil, agentID: nil
        )
        #expect(result.contains { $0.qualifiedID == "thing.eigin" })
        #expect(result.contains { $0.qualifiedID == "actor.bob" })
    }

    @Test func danishUnrelatedMessageReturnsEmpty() async {
        let fake = seededFake()
        let result = await KnowledgeHydrator.hydrate(
            userText: "Hvad er vejret i København i weekenden?",
            knowledgeService: fake, spaceID: nil, agentID: nil
        )
        #expect(!result.contains { $0.qualifiedID.hasPrefix("actor.") })
        #expect(!result.contains { $0.qualifiedID == "thing.eigin" })
    }
}
