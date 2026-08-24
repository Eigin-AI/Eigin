@testable import Eigin
import Foundation
import Testing

@Suite("MemoryConsolidation")
@MainActor
struct MemoryConsolidationTests {
    private let now = Date()

    private func namedEntity(type: String, id: String, name: String) -> FirmEntity {
        FirmEntity(
            id: "\(type).\(id)",
            entityType: type,
            fields: [FirmField(name: "name", value: .string(value: name))]
        )
    }

    private func source(
        type: String, id: String, embedding: [Double],
        accessCount: Double = 1, lastAccessedAt: Date? = nil,
        importance: Double = 0.5, expired: Bool = false, contested: Bool = false,
        lastReviewedAt: Date? = nil
    ) -> FirmSource {
        let path = BundledKnowledge.entityPath(
            prefix: BundledKnowledge.knowledgePrefix, type: type, id: id
        )
        let fs = FirmSource(path: path, content: "")
        fs.embedding = embedding
        fs.accessCount = accessCount
        fs.lastAccessedAt = lastAccessedAt
        fs.importance = importance
        fs.expired = expired
        fs.contested = contested
        fs.lastReviewedAt = lastReviewedAt
        return fs
    }

    private func unit(_ i: Int) -> [Double] {
        var v = [0.0, 0.0, 0.0]
        v[i] = 1.0
        return v
    }

    private func daysAgo(_ d: Double) -> Date {
        now.addingTimeInterval(-d * 86400)
    }

    private func fresh() -> FakeKnowledgeService {
        let f = FakeKnowledgeService()
        f.entities["fact.likes_tea"] = namedEntity(type: "fact", id: "likes_tea", name: "Likes tea")
        f.entities["fact.likes_green_tea"] =
            namedEntity(type: "fact", id: "likes_green_tea", name: "Likes green tea")
        return f
    }

    @Test func groupsNearDuplicatesIntoACluster() async {
        let f = fresh()
        f.sources = [
            source(type: "fact", id: "likes_tea", embedding: unit(0), lastAccessedAt: now),
            source(type: "fact", id: "likes_green_tea", embedding: unit(0), lastAccessedAt: now),
        ]

        let candidates = await MemoryConsolidation.candidates(
            knowledgeService: f, spaceID: nil, agentID: nil, now: now
        )

        #expect(candidates.duplicateClusters.count == 1)
        let ids = Set(candidates.duplicateClusters[0].map(\.qualifiedID))
        #expect(ids == ["fact.likes_tea", "fact.likes_green_tea"])
    }

    @Test func capsLargeClusterToCohesiveCore() async {
        let f = FakeKnowledgeService()
        let n = MemoryConsolidation.maxClusterMembers + 2
        for i in 0 ..< n {
            f.entities["fact.dup_\(i)"] = namedEntity(
                type: "fact",
                id: "dup_\(i)",
                name: "Dup \(i)"
            )
        }
        f.sources = (0 ..< n).map {
            source(type: "fact", id: "dup_\($0)", embedding: unit(0), lastAccessedAt: now)
        }

        let candidates = await MemoryConsolidation.candidates(
            knowledgeService: f, spaceID: nil, agentID: nil, now: now
        )

        #expect(candidates.duplicateClusters.count == 1)
        #expect(candidates.duplicateClusters[0].count == MemoryConsolidation.maxClusterMembers)
    }

    @Test func ranksTighterClusterFirst() async {
        let f = FakeKnowledgeService()
        for id in ["x1", "x2", "y1", "y2"] {
            f.entities["fact.\(id)"] = namedEntity(type: "fact", id: id, name: id)
        }
        // Cluster X: cosine 1.0. Cluster Y: cosine ~0.86 (just above threshold).
        f.sources = [
            source(type: "fact", id: "x1", embedding: [1, 0, 0], lastAccessedAt: now),
            source(type: "fact", id: "x2", embedding: [1, 0, 0], lastAccessedAt: now),
            source(type: "fact", id: "y1", embedding: [0, 0, 1], lastAccessedAt: now),
            source(type: "fact", id: "y2", embedding: [0, 0.51, 0.86], lastAccessedAt: now),
        ]

        let candidates = await MemoryConsolidation.candidates(
            knowledgeService: f, spaceID: nil, agentID: nil, now: now
        )

        #expect(candidates.duplicateClusters.count == 2)
        #expect(Set(candidates.duplicateClusters[0].map(\.qualifiedID)) == ["fact.x1", "fact.x2"])
    }

    @Test func unreviewedClusterOutranksRecentlyReviewed() async {
        let f = FakeKnowledgeService()
        for id in ["x1", "x2", "y1", "y2"] {
            f.entities["fact.\(id)"] = namedEntity(type: "fact", id: id, name: id)
        }
        // Cluster X is tighter (cosine 1.0) but was just reviewed; cluster Y is
        // looser (~0.86) but never reviewed → Y should lead, so we rotate.
        f.sources = [
            source(
                type: "fact",
                id: "x1",
                embedding: [1, 0, 0],
                lastAccessedAt: now,
                lastReviewedAt: now
            ),
            source(
                type: "fact",
                id: "x2",
                embedding: [1, 0, 0],
                lastAccessedAt: now,
                lastReviewedAt: now
            ),
            source(type: "fact", id: "y1", embedding: [0, 0, 1], lastAccessedAt: now),
            source(type: "fact", id: "y2", embedding: [0, 0.51, 0.86], lastAccessedAt: now),
        ]

        let candidates = await MemoryConsolidation.candidates(
            knowledgeService: f, spaceID: nil, agentID: nil, now: now
        )

        #expect(candidates.duplicateClusters.count == 2)
        #expect(Set(candidates.duplicateClusters[0].map(\.qualifiedID)) == ["fact.y1", "fact.y2"])
    }

    @Test func reportsAllSurfacedMembersIncludingTrimmed() async {
        let f = FakeKnowledgeService()
        let n = MemoryConsolidation.maxClusterMembers + 2
        for i in 0 ..< n {
            f.entities["fact.dup_\(i)"] = namedEntity(
                type: "fact",
                id: "dup_\(i)",
                name: "Dup \(i)"
            )
        }
        f.sources = (0 ..< n).map {
            source(type: "fact", id: "dup_\($0)", embedding: unit(0), lastAccessedAt: now)
        }

        let candidates = await MemoryConsolidation.candidates(
            knowledgeService: f, spaceID: nil, agentID: nil, now: now
        )

        // Display is capped, but every member is stamped so the core doesn't
        // resurface next run because of a still-unreviewed peripheral member.
        #expect(candidates.duplicateClusters[0].count == MemoryConsolidation.maxClusterMembers)
        #expect(Set(candidates.reviewedIDs).count == n)
    }

    @Test func distinctMemoriesAreNotClustered() async {
        let f = fresh()
        f.sources = [
            source(type: "fact", id: "likes_tea", embedding: unit(0), lastAccessedAt: now),
            source(type: "fact", id: "likes_green_tea", embedding: unit(1), lastAccessedAt: now),
        ]

        let candidates = await MemoryConsolidation.candidates(
            knowledgeService: f, spaceID: nil, agentID: nil, now: now
        )

        #expect(candidates.duplicateClusters.isEmpty)
    }

    @Test func surfacesStaleLowStakesEviction() async {
        let f = FakeKnowledgeService()
        f.entities["note.old_thought"] = namedEntity(
            type: "note",
            id: "old_thought",
            name: "A passing idea"
        )
        f.sources = [source(
            type: "note", id: "old_thought", embedding: unit(0),
            accessCount: 1, lastAccessedAt: daysAgo(120), importance: 0.3
        )]

        let candidates = await MemoryConsolidation.candidates(
            knowledgeService: f, spaceID: nil, agentID: nil, now: now
        )

        #expect(candidates.evictionCandidates.map(\.qualifiedID) == ["note.old_thought"])
    }

    @Test func protectsRecentImportantAndFrequent() async {
        let f = FakeKnowledgeService()
        f.entities["note.recent"] = namedEntity(type: "note", id: "recent", name: "Recent")
        f.entities["fact.allergy"] = namedEntity(
            type: "fact",
            id: "allergy",
            name: "Penicillin allergy"
        )
        f.entities["thing.coffee"] = namedEntity(type: "thing", id: "coffee", name: "Coffee")
        f.sources = [
            // Recently touched → within grace period.
            source(
                type: "note",
                id: "recent",
                embedding: unit(0),
                accessCount: 1,
                lastAccessedAt: daysAgo(3),
                importance: 0.3
            ),
            // Old but critical → importance safety net.
            source(
                type: "fact",
                id: "allergy",
                embedding: unit(1),
                accessCount: 1,
                lastAccessedAt: daysAgo(200),
                importance: 0.95
            ),
            // Old but historically frequent → activation stays high.
            source(
                type: "thing",
                id: "coffee",
                embedding: unit(2),
                accessCount: 15,
                lastAccessedAt: daysAgo(200),
                importance: 0.3
            ),
        ]

        let candidates = await MemoryConsolidation.candidates(
            knowledgeService: f, spaceID: nil, agentID: nil, now: now
        )

        #expect(candidates.evictionCandidates.isEmpty)
    }

    @Test func excludesExpiredAndContested() async {
        let f = fresh()
        f.sources = [
            source(
                type: "fact",
                id: "likes_tea",
                embedding: unit(0),
                lastAccessedAt: now,
                expired: true
            ),
            source(
                type: "fact",
                id: "likes_green_tea",
                embedding: unit(0),
                lastAccessedAt: now,
                contested: true
            ),
        ]

        let candidates = await MemoryConsolidation.candidates(
            knowledgeService: f, spaceID: nil, agentID: nil, now: now
        )

        #expect(candidates.isEmpty)
    }

    @Test func promptSectionEmptyWhenNothingFlagged() async {
        let f = FakeKnowledgeService()
        f.entities["fact.solo"] = namedEntity(type: "fact", id: "solo", name: "Solo fact")
        f.sources = [source(type: "fact", id: "solo", embedding: unit(0), lastAccessedAt: now)]

        let candidates = await MemoryConsolidation.candidates(
            knowledgeService: f, spaceID: nil, agentID: nil, now: now
        )

        #expect(candidates.isEmpty)
        #expect(candidates.promptSection().isEmpty)
    }
}
