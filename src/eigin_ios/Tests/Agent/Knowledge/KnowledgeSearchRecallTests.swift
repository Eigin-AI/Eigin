@testable import Eigin
import Foundation
import Testing

extension KnowledgeSearchEngineTests {
    // MARK: - Issue #353

    @Test(arguments: [
        "john_doe_router",
        "ACTOR.JOHN_DOE_ROUTER",
        "John Doe Router",
        "John Doe",
    ])
    func exactIdentityBeatsMoreThanTenBoostedHubs(query: String) async throws {
        let fake = FakeKnowledgeService()
        fake.entities["actor.john_doe_router"] = namedEntity(
            type: "actor", id: "john_doe_router", name: "John Doe"
        )
        for i in 0 ..< 12 {
            let id = "hub_\(i)"
            fake.entities["note.\(id)"] = namedEntity(type: "note", id: id, name: "Strategy")
            fake.sources.append(source(
                type: "note", id: id, embedding: unit(0),
                accessCount: 1_000_000, lastAccessedAt: Date(), importance: 1
            ))
        }
        let ranked = try await KnowledgeSearchEngine.score(
            queryEmbedding: unit(0), keywordNeedle: query,
            knowledgeService: fake, spaceID: nil, agentID: nil
        ).sorted(by: KnowledgeSearchEngine.ranksBefore)
        #expect(ranked.prefix(10).first?.qualifiedID == "actor.john_doe_router")
    }

    @Test func fullQueryCoverageBeatsReadingOnlyAndBoostedHubs() async throws {
        let fake = FakeKnowledgeService()
        fake.entities["note.preferences"] = FirmEntity(
            id: "preferences", entityType: "note", fields: [
                FirmField(name: "subject", value: .string(value: "Preferences")),
                FirmField(name: "body", value: .string(value: "Reading books on paper")),
            ]
        )
        fake.entities["note.hub"] = namedEntity(type: "note", id: "hub", name: "Reading news")
        fake.sources = [source(
            type: "note", id: "hub", embedding: unit(0),
            accessCount: 1_000_000, lastAccessedAt: Date(), importance: 1
        )]
        let ranked = try await KnowledgeSearchEngine.score(
            queryEmbedding: unit(0), keywordNeedle: "reading preferences",
            knowledgeService: fake, spaceID: nil, agentID: nil
        ).sorted(by: KnowledgeSearchEngine.ranksBefore)
        #expect(ranked.first?.qualifiedID == "note.preferences")
        #expect(ranked.first?.relevance == KnowledgeLexicalMatcher.fullCoverageScore)
    }

    @Test func referencesAndBodyMentionsStayBelowOwnIdentity() async throws {
        let fake = FakeKnowledgeService()
        fake.entities["actor.user"] = namedEntity(
            type: "actor",
            id: "user",
            name: "John Doe"
        )
        fake.entities["note.mention"] = FirmEntity(
            id: "note.mention", entityType: "note", fields: [
                FirmField(name: "about", value: .entityReference(entityId: "actor.user")),
                FirmField(name: "body", value: .string(value: "John Doe")),
            ]
        )
        for query in ["actor.user", "user", "John Doe"] {
            let ranked = try await KnowledgeSearchEngine.score(
                queryEmbedding: [], keywordNeedle: query,
                knowledgeService: fake, spaceID: nil, agentID: nil
            ).sorted(by: KnowledgeSearchEngine.ranksBefore)
            #expect(ranked.first?.qualifiedID == "actor.user")
            #expect(ranked.count == 2)
        }
    }

    @Test func equalLexicalScoresUseStableIDsAndRespectLimit() async throws {
        let fake = FakeKnowledgeService()
        for id in ["z", "b", "a"] {
            fake.entities["note.\(id)"] = namedEntity(
                type: "note",
                id: id,
                name: "Reading preferences"
            )
        }
        let results = try await KnowledgeSearchEngine.search(
            query: "reading preferences", threshold: 1.1, limit: 2,
            knowledgeService: fake, spaceID: nil, agentID: nil
        )
        #expect(results.map(\.qualifiedID) == ["note.a", "note.b"])
    }

    @Test func semanticBoostCannotReplaceStrongQueryEvidence() async throws {
        let fake = twoActorsSameAxis()
        fake.sources = [
            source(
                type: "actor",
                id: "a",
                embedding: [0.5, sqrt(0.75), 0],
                accessCount: 1_000_000,
                lastAccessedAt: Date(),
                importance: 1
            ),
            source(
                type: "actor",
                id: "b",
                embedding: [0.7, sqrt(0.51), 0],
                accessCount: 0,
                lastAccessedAt: nil
            ),
        ]
        let ranked = try await KnowledgeSearchEngine.score(
            queryEmbedding: unit(0), knowledgeService: fake, spaceID: nil, agentID: nil
        ).sorted(by: KnowledgeSearchEngine.ranksBefore)
        #expect(ranked.first?.qualifiedID == "actor.b")
        #expect(ranked.allSatisfy { abs($0.score - $0.relevance) <= 0.05 })
    }

    @Test func searchExposureDoesNotCountAsAccessButExplicitReadDoes() async {
        let fake = seededFake()
        let agent = Agent(name: "Test", providerID: UUID(), model: "test")
        let search = SearchKnowledgeTool(knowledgeService: fake, spaceID: nil, agentID: nil)
        let call = ToolCall(id: "search", type: "function", function: .init(
            name: "search_knowledge", arguments: #"{"query":"alice"}"#
        ))
        for _ in 0 ..< 3 {
            let result = await search.execute(call, agent: agent)
            #expect(!result.isError)
            #expect(result.content.contains("actor.alice"))
        }
        #expect(fake.accessedIDs.isEmpty)
        let get = GetKnowledgeTool(knowledgeService: fake, spaceID: nil, agentID: nil)
        let result = await get.execute(ToolCall(id: "get", type: "function", function: .init(
            name: "get_knowledge", arguments: #"{"type":"actor","id":"alice"}"#
        )), agent: agent)
        #expect(!result.isError)
        #expect(fake.accessedIDs == ["actor.alice"])
    }

    @Test func qualifiedIDBeatsCollidingShortID() async throws {
        let fake = FakeKnowledgeService()
        fake.entities["actor.user"] = namedEntity(type: "actor", id: "user", name: "John")
        fake.entities["note.actor_user"] = namedEntity(
            type: "note",
            id: "actor_user",
            name: "Mention"
        )
        fake.sources = [source(
            type: "note", id: "actor_user", embedding: unit(0),
            accessCount: 1_000_000, lastAccessedAt: Date(), importance: 1
        )]
        let results = try await KnowledgeSearchEngine.score(
            queryEmbedding: unit(0), keywordNeedle: "actor.user",
            knowledgeService: fake, spaceID: nil, agentID: nil
        ).sorted(by: KnowledgeSearchEngine.ranksBefore)
        #expect(results.first?.qualifiedID == "actor.user")
    }

    @Test(arguments: ["draft_v1", "note.draft_v1", "draftV1"])
    func firmNormalizedIDsPreserveExactRecall(query: String) async throws {
        let fake = FakeKnowledgeService()
        fake.entities["note.draft_v_1"] = namedEntity(type: "note", id: "draft_v_1", name: "Draft")
        let results = try await KnowledgeSearchEngine.score(
            queryEmbedding: [], keywordNeedle: query,
            knowledgeService: fake, spaceID: nil, agentID: nil
        )
        #expect(try #require(results.first).relevance >= KnowledgeLexicalMatcher.exactIDScore)
    }

    @Test func lexicalBandsStayProtectedWhenMemoryWeightsAreRetuned() {
        let tiers = [
            1.0,
            KnowledgeLexicalMatcher.fullCoverageScore,
            KnowledgeLexicalMatcher.identityPhraseScore,
            KnowledgeLexicalMatcher.exactNameScore,
            KnowledgeLexicalMatcher.exactIDScore,
            KnowledgeLexicalMatcher.qualifiedIDScore,
        ]
        for (lower, upper) in zip(tiers, tiers.dropFirst()) {
            #expect(KnowledgeSearchEngine.rankingScore(relevance: lower, adjustment: 100) <
                KnowledgeSearchEngine.rankingScore(relevance: upper, adjustment: -100))
        }
    }

    @Test func boostedSubthresholdConflictCandidateIsRejected() async {
        let fake = twoActorsSameAxis()
        fake.sources = [
            source(
                type: "actor",
                id: "a",
                embedding: [0.84, sqrt(1 - 0.84 * 0.84), 0],
                accessCount: 1_000_000,
                lastAccessedAt: Date(),
                importance: 1
            ),
            source(
                type: "actor",
                id: "b",
                embedding: unit(0),
                accessCount: 0,
                lastAccessedAt: nil
            ),
        ]
        let hints = await KnowledgeConflictHint.similarExisting(
            queryEmbedding: unit(0), excluding: "note.self",
            knowledgeService: fake, spaceID: nil, agentID: nil
        )
        #expect(hints.compactMap { $0["id"] as? String } == ["actor.b"])
    }
}
