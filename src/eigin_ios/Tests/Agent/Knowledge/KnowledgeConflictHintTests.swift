@testable import Eigin
import Foundation
import Testing

@Suite("KnowledgeConflictHint")
@MainActor
struct KnowledgeConflictHintTests {
    private func namedEntity(type: String, id: String, name: String) -> FirmEntity {
        FirmEntity(
            id: "\(type).\(id)",
            entityType: type,
            fields: [FirmField(name: "name", value: .string(value: name))]
        )
    }

    private func source(type: String, id: String, embedding: [Double]) -> FirmSource {
        let path = BundledKnowledge.entityPath(
            prefix: BundledKnowledge.knowledgePrefix, type: type, id: id
        )
        let fs = FirmSource(path: path, content: "")
        fs.embedding = embedding
        return fs
    }

    private func unit(_ i: Int) -> [Double] {
        var v = [0.0, 0.0, 0.0]
        v[i] = 1.0
        return v
    }

    private func ids(_ hints: [[String: Any]]) -> [String] {
        hints.compactMap { $0["id"] as? String }
    }

    @Test func surfacesNearDuplicate() async {
        let fake = FakeKnowledgeService()
        fake.entities["fact.likes_tea"] = namedEntity(
            type: "fact",
            id: "likes_tea",
            name: "Likes tea"
        )
        fake.entities["fact.unrelated"] = namedEntity(
            type: "fact",
            id: "unrelated",
            name: "Owns a bike"
        )
        fake.sources = [
            source(type: "fact", id: "likes_tea", embedding: unit(0)),
            source(type: "fact", id: "unrelated", embedding: unit(1)),
        ]

        // A brand-new memory pointing at the same axis as likes_tea.
        let hints = await KnowledgeConflictHint.similarExisting(
            queryEmbedding: unit(0),
            excluding: "fact.likes_green_tea",
            knowledgeService: fake, spaceID: nil, agentID: nil
        )

        #expect(ids(hints) == ["fact.likes_tea"])
    }

    @Test func silentWhenNothingClose() async {
        let fake = FakeKnowledgeService()
        fake.entities["fact.unrelated"] = namedEntity(
            type: "fact",
            id: "unrelated",
            name: "Owns a bike"
        )
        fake.sources = [source(type: "fact", id: "unrelated", embedding: unit(1))]

        let hints = await KnowledgeConflictHint.similarExisting(
            queryEmbedding: unit(0),
            excluding: "fact.likes_tea",
            knowledgeService: fake, spaceID: nil, agentID: nil
        )

        #expect(hints.isEmpty)
    }

    @Test func excludesSelf() async {
        let fake = FakeKnowledgeService()
        fake.entities["fact.likes_tea"] = namedEntity(
            type: "fact",
            id: "likes_tea",
            name: "Likes tea"
        )
        fake.sources = [source(type: "fact", id: "likes_tea", embedding: unit(0))]

        // Scanning the same entity that already lives in the corpus at cosine 1.
        let hints = await KnowledgeConflictHint.similarExisting(
            queryEmbedding: unit(0),
            excluding: "fact.likes_tea",
            knowledgeService: fake, spaceID: nil, agentID: nil
        )

        #expect(hints.isEmpty)
    }
}
