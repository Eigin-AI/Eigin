@testable import Eigin
import Foundation
import Testing

@Suite("KnowledgeSearchEngine")
@MainActor
struct KnowledgeSearchEngineTests {
    // MARK: - Fixtures

    /// Make a bare entity with a name field.
    private func namedEntity(type: String, id: String, name: String) -> FirmEntity {
        FirmEntity(
            id: "\(type).\(id)",
            entityType: type,
            fields: [FirmField(name: "name", value: .string(value: name))]
        )
    }

    /// Make a FirmSource with a fixed embedding vector.
    private func source(type: String, id: String, embedding: [Double]) -> FirmSource {
        let path = BundledKnowledge.entityPath(
            prefix: BundledKnowledge.knowledgePrefix, type: type, id: id
        )
        let fs = FirmSource(path: path, content: "")
        fs.embedding = embedding
        return fs
    }

    /// Unit vector along axis `i` in a 3-dim vector space. Cosine similarity
    /// between any two such vectors is 1 if the same axis, 0 if different.
    private func unit(_ i: Int) -> [Double] {
        var v = [0.0, 0.0, 0.0]
        v[i] = 1.0
        return v
    }

    /// Build a fake seeded with three entities along orthogonal axes so
    /// cosine similarity is fully deterministic for tests.
    private func seededFake() -> FakeKnowledgeService {
        let fake = FakeKnowledgeService()
        let alice = namedEntity(type: "actor", id: "alice", name: "Alice")
        let bob = namedEntity(type: "actor", id: "bob", name: "Bob")
        let coffee = namedEntity(type: "thing", id: "coffee", name: "Coffee")

        fake.entities["actor.alice"] = alice
        fake.entities["actor.bob"] = bob
        fake.entities["thing.coffee"] = coffee

        fake.sources = [
            source(type: "actor", id: "alice", embedding: unit(0)),
            source(type: "actor", id: "bob", embedding: unit(1)),
            source(type: "thing", id: "coffee", embedding: unit(2)),
        ]
        return fake
    }

    // MARK: - score()

    @Test func scoreMatchesEmbeddingAxis() async throws {
        let fake = seededFake()
        let results = try await KnowledgeSearchEngine.score(
            queryEmbedding: unit(0),
            knowledgeService: fake,
            spaceID: nil,
            agentID: nil
        )
        // alice on axis 0 → score 1.0; bob and coffee on other axes → score 0
        // and get filtered out.
        #expect(results.count == 1)
        #expect(results.first?.qualifiedID == "actor.alice")
        #expect(results.first?.score == 1.0)
    }

    @Test func scoreFiltersZero() async throws {
        let fake = seededFake()
        // Query along an axis orthogonal to every entity → nothing scores.
        let results = try await KnowledgeSearchEngine.score(
            queryEmbedding: [0, 0, 0, 1],
            knowledgeService: fake,
            spaceID: nil,
            agentID: nil
        )
        #expect(results.isEmpty)
    }

    @Test func scoreSkipsEntitiesWithoutEmbeddings() async throws {
        let fake = seededFake()
        // Drop alice's embedding
        fake.sources = fake.sources.filter { !$0.path.contains("alice") }
        let results = try await KnowledgeSearchEngine.score(
            queryEmbedding: unit(0),
            knowledgeService: fake,
            spaceID: nil,
            agentID: nil
        )
        #expect(results.isEmpty)
    }

    @Test func scoreKeywordNeedleMatchesName() async throws {
        let fake = seededFake()
        // Empty query embedding → no cosine signal. Keyword "alice" hits the
        // name field → 0.5 score.
        let results = try await KnowledgeSearchEngine.score(
            queryEmbedding: [],
            keywordNeedle: "alice",
            knowledgeService: fake,
            spaceID: nil,
            agentID: nil
        )
        #expect(results.contains { $0.qualifiedID == "actor.alice" && $0.score == 0.5 })
    }

    @Test func scoreTakesMaxOfEmbeddingAndKeyword() async throws {
        let fake = seededFake()
        // Query on axis 0 (cosine 1.0 for alice) AND keyword "alice"
        // (0.5) — max = 1.0
        let results = try await KnowledgeSearchEngine.score(
            queryEmbedding: unit(0),
            keywordNeedle: "alice",
            knowledgeService: fake,
            spaceID: nil,
            agentID: nil
        )
        let alice = results.first { $0.qualifiedID == "actor.alice" }
        #expect(alice?.score == 1.0)
    }

    @Test func scoreTypeFilterRestrictsResults() async throws {
        let fake = seededFake()
        // Alice + Bob + Coffee embedded along all three axes; query a vector
        // equally close to all. Type-filtered search should only return
        // actors.
        let results = try await KnowledgeSearchEngine.score(
            queryEmbedding: [1, 1, 1],
            keywordNeedle: nil,
            typeFilter: "actor",
            knowledgeService: fake,
            spaceID: nil,
            agentID: nil
        )
        let types = Set(results.map(\.entity.entityType))
        #expect(types == ["actor"])
    }

    @Test func scoreForwardsScopeToService() async throws {
        let fake = seededFake()
        let spaceID = UUID()
        let agentID = UUID()
        _ = try await KnowledgeSearchEngine.score(
            queryEmbedding: unit(0),
            knowledgeService: fake,
            spaceID: spaceID,
            agentID: agentID
        )
        #expect(fake.receivedSpaceIDs.allSatisfy { $0 == spaceID })
        #expect(fake.receivedAgentIDs.allSatisfy { $0 == agentID })
    }

    // MARK: - search()

    @Test func searchAppliesThresholdAndLimit() async throws {
        let fake = seededFake()
        let results = try await KnowledgeSearchEngine.search(
            query: "alice",
            threshold: 0.4,
            limit: 5,
            knowledgeService: fake,
            spaceID: nil,
            agentID: nil
        )
        // Keyword match hits alice (0.5); threshold 0.4 keeps it; limit 5
        // is generous.
        #expect(results.contains { $0.qualifiedID == "actor.alice" })
    }

    @Test func searchSortsDescending() async throws {
        let fake = seededFake()
        // Add an expired-free second actor with an embedding that matches
        // the query less closely.
        let diluted = namedEntity(type: "actor", id: "carol", name: "Carol")
        fake.entities["actor.carol"] = diluted
        fake.sources.append(source(type: "actor", id: "carol", embedding: [0.5, 0.5, 0]))

        let results = try await KnowledgeSearchEngine.search(
            query: "",
            threshold: 0,
            limit: 10,
            knowledgeService: fake,
            spaceID: nil,
            agentID: nil
        )
        // Sorted descending: whatever the order, scores are non-increasing.
        var last = Double.infinity
        for r in results {
            #expect(r.score <= last)
            last = r.score
        }
    }
}
