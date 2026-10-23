@testable import Eigin
import Foundation
import Testing

@Suite("Knowledge library")
@MainActor
struct KnowledgeLibraryTests {
    private func entity(_ type: String, _ id: String, fields: [FirmField] = []) -> FirmEntity {
        FirmEntity(id: "\(type).\(id)", entityType: type, fields: fields)
    }

    @Test func loadsCanonicalCategoriesWithFourItemPreviewsAndCompleteLists() async throws {
        let service = FakeKnowledgeService()
        let agentID = UUID()
        let things = (0 ..< 7).map { entity("thing", "item_\($0)") }
        let facts = (0 ..< 4).map { entity("fact", "fact_\($0)") }
        let records = things + facts + [
            entity("actor", "user"),
            entity("note", "draft"),
            entity("custom", "hidden"),
        ]
        service.entities = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        let library = KnowledgeLibrary(service: service, agentID: agentID)
        await library.load()
        #expect(library.categories.map(\.type) == ["actor", "thing", "fact", "note"])
        let category = try #require(library.categories.first { $0.type == "thing" })
        #expect(category.preview.count == 4)
        #expect(category.items.count == 7)
        #expect(category.hasMore)
        #expect(library.categories.first { $0.type == "fact" }?.hasMore == false)
        #expect(service.receivedAgentIDs.allSatisfy { $0 == agentID })
        #expect(!library.isLoading)
        #expect(library.error == nil)
    }

    @Test func ordersFullTimestampsNewestFirstAndUndatedEntriesLast() async {
        let service = FakeKnowledgeService()
        let records = [
            entity(
                "fact",
                "older",
                fields: [.init(name: "created_at", value: .dateTime(value: "2026-10-19T09:00:00Z"))]
            ),
            entity(
                "fact",
                "newer",
                fields: [.init(name: "created_at", value: .dateTime(value: "2026-10-19T12:30:00Z"))]
            ),
            entity(
                "fact",
                "dated",
                fields: [.init(name: "created_at", value: .dateTime(value: "2025-01-01"))]
            ),
            entity("fact", "undated"),
        ]
        service.entities = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        let library = KnowledgeLibrary(service: service, agentID: nil)
        await library.load()
        #expect(library.categories.first?.items.map(\.id) == [
            "fact.newer",
            "fact.older",
            "fact.dated",
            "fact.undated",
        ])
    }

    @Test func successfulDeletionUpdatesPreviewAndFullListWithoutChangingOpaqueIDs() async throws {
        let service = FakeKnowledgeService()
        let id = "v1.with.dots"
        let records = (0 ..< 4).map { entity("note", "draft_\($0)") } + [entity("note", id)]
        service.entities = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        let library = KnowledgeLibrary(service: service, agentID: nil)
        await library.load()
        let item = try #require(service.entities["note.\(id)"])
        let details = KnowledgeDetails(entity: item, service: service, agentID: nil)
        #expect(await details.delete())
        library.remove(item.id)
        #expect(service.entities[item.id] == nil)
        #expect(library.categories.first?.items.count == 4)
        #expect(library.categories.first?.hasMore == false)
        #expect(library.categories.first?.preview.count == 4)
        for record in records {
            library.remove(record.id)
        }
        #expect(library.categories.isEmpty)
    }

    @Test func refreshFailurePreservesCategoriesAndCanBeRetried() async {
        let service = FakeKnowledgeService()
        service.entities["note.draft"] = entity("note", "draft")
        let library = KnowledgeLibrary(service: service, agentID: nil)
        await library.load()
        service.throwOnListSchemas = true
        await library.load()
        #expect(library.error != nil)
        #expect(library.categories.first?.items.first?.id == "note.draft")
        #expect(!library.isLoading)
        service.throwOnListSchemas = false
        await library.load()
        #expect(library.error == nil)
        #expect(library.categories.first?.items.count == 1)
    }

    @Test func cancelledLoadDoesNotPublishPartialCategories() async {
        let service = FakeKnowledgeService()
        service.entities["actor.user"] = entity("actor", "user")
        let library = KnowledgeLibrary(service: service, agentID: nil)
        await library.load()
        let before = library.categories.flatMap(\.items).map(\.id)
        let task = Task { await library.load() }
        task.cancel()
        await task.value
        #expect(library.categories.flatMap(\.items).map(\.id) == before)
        #expect(library.error == nil)
    }
}
