@testable import Eigin
import Foundation
import Testing

@Suite("KnowledgeGraphViewModel")
struct KnowledgeGraphViewModelTests {
    // MARK: - Fake Knowledge Service

    final class FakeGraphKnowledgeService: KnowledgeService, @unchecked Sendable {
        var isBuilt: Bool {
            true
        }

        var entities: [String: FirmEntity] = [:]
        var relations: [String: [FirmEntity]] = [:] // key: "type.id"

        func rebuild(
            spaceID: UUID?,
            agentID: UUID?,
            accessPolicy: SpaceAccessPolicy?
        ) async throws {}
        func query(
            _ queryString: String,
            spaceID: UUID?,
            agentID: UUID?
        ) async throws -> FirmQueryResult {
            .entities(entities: [])
        }

        func getEntity(
            type: String,
            id: String,
            spaceID: UUID?,
            agentID: UUID?
        ) async throws -> FirmEntity? {
            entities["\(type).\(id)"]
        }

        func listEntities(type: String, spaceID: UUID?, agentID: UUID?) async throws -> [String] {
            entities.values.filter { $0.entityType == type }.map {
                let prefix = type + "."
                return $0.id.hasPrefix(prefix) ? String($0.id.dropFirst(prefix.count)) : $0.id
            }
        }

        func listSchemas(spaceID: UUID?, agentID: UUID?) async throws -> [String] {
            Array(Set(entities.values.map(\.entityType)))
        }

        func getRelated(
            type: String,
            id: String,
            direction: FirmDirection,
            spaceID: UUID?,
            agentID: UUID?
        ) async throws -> [FirmEntity] {
            relations["\(type).\(id)"] ?? []
        }

        func addEntity(
            _ entity: FirmEntity,
            spaceID: UUID?,
            agentID: UUID?,
            chatID: UUID?
        ) async throws {}
        func deleteEntity(type: String, id: String, spaceID: UUID?, agentID: UUID?) async throws {}
        func isBundled(path: String) -> Bool {
            false
        }

        func getSource(path: String, spaceID: UUID?, agentID: UUID?) async throws -> String? {
            nil
        }

        func findEntitySource(
            type: String,
            id: String,
            spaceID: UUID?,
            agentID: UUID?
        ) async throws -> String? {
            nil
        }

        func getSchema(
            entityType: String,
            spaceID: UUID?,
            agentID: UUID?
        ) async throws -> FirmSchema? {
            nil
        }

        func getFirmSource(
            type: String,
            id: String,
            spaceID: UUID?,
            agentID: UUID?
        ) async throws -> FirmSource? {
            nil
        }

        func allVisibleSources(spaceID: UUID?, agentID: UUID?) async throws -> [FirmSource] {
            []
        }

        func validEntities(
            type: String,
            spaceID: UUID?,
            agentID: UUID?,
            at date: Date
        ) async throws -> [FirmEntity] {
            []
        }
    }

    // MARK: - Helpers

    private func makeEntity(type: String, id: String, name: String) -> FirmEntity {
        FirmEntity(
            id: "\(type).\(id)",
            entityType: type,
            fields: [FirmField(name: "name", value: .string(value: name))]
        )
    }

    // MARK: - Focus Traversal

    @Test("Initial load focuses on actor entity when one exists")
    @MainActor
    func initialLoadFocusesActor() async {
        let service = FakeGraphKnowledgeService()
        let actor = makeEntity(type: "actor", id: "alice", name: "Alice")
        let thing = makeEntity(type: "thing", id: "phone", name: "Phone")
        service.entities = ["actor.alice": actor, "thing.phone": thing]
        service.relations = [
            "actor.alice": [thing],
            "thing.phone": [actor],
        ]

        let vm = KnowledgeGraphViewModel(knowledgeService: service, agentID: nil)
        await vm.loadInitialGraph()

        #expect(vm.focusID == "actor.alice")
        #expect(!vm.isLoading)
    }

    @Test("Focus change updates nodes and breadcrumbs")
    @MainActor
    func focusChange() async {
        let service = FakeGraphKnowledgeService()
        let actor = makeEntity(type: "actor", id: "alice", name: "Alice")
        let thing = makeEntity(type: "thing", id: "phone", name: "Phone")
        service.entities = ["actor.alice": actor, "thing.phone": thing]
        service.relations = [
            "actor.alice": [thing],
            "thing.phone": [actor],
        ]

        let vm = KnowledgeGraphViewModel(knowledgeService: service, agentID: nil)
        await vm.loadInitialGraph()
        await vm.focusOn(entityID: "thing.phone")

        #expect(vm.focusID == "thing.phone")
    }

    // MARK: - Node Caching

    @Test("Neighbors are cached across focus changes")
    @MainActor
    func neighborCaching() async {
        let service = FakeGraphKnowledgeService()
        let actor = makeEntity(type: "actor", id: "alice", name: "Alice")
        let thing = makeEntity(type: "thing", id: "phone", name: "Phone")
        let fact = makeEntity(type: "fact", id: "f1", name: "A fact")
        service.entities = ["actor.alice": actor, "thing.phone": thing, "fact.f1": fact]
        service.relations = [
            "actor.alice": [thing],
            "thing.phone": [actor, fact],
            "fact.f1": [thing],
        ]

        let vm = KnowledgeGraphViewModel(knowledgeService: service, agentID: nil)
        await vm.loadInitialGraph()

        // Focus on thing.phone — should show actor.alice as hop-1 and fact.f1 as hop-1.
        await vm.focusOn(entityID: "thing.phone")

        #expect(vm.nodes.contains { $0.id == "fact.f1" })
        #expect(vm.nodes.contains { $0.id == "actor.alice" })
    }

    // MARK: - Edges

    @Test("Edges are deduplicated between connected nodes")
    @MainActor
    func edgeDeduplication() async {
        let service = FakeGraphKnowledgeService()
        let actor = makeEntity(type: "actor", id: "alice", name: "Alice")
        let thing = makeEntity(type: "thing", id: "phone", name: "Phone")
        service.entities = ["actor.alice": actor, "thing.phone": thing]
        // Bidirectional relationship.
        service.relations = [
            "actor.alice": [thing],
            "thing.phone": [actor],
        ]

        let vm = KnowledgeGraphViewModel(knowledgeService: service, agentID: nil)
        await vm.loadInitialGraph()

        // Should have exactly one edge between actor.alice and thing.phone.
        let edges = vm.edges.filter {
            ($0.sourceID == "actor.alice" && $0.targetID == "thing.phone") ||
                ($0.sourceID == "thing.phone" && $0.targetID == "actor.alice")
        }
        #expect(edges.count == 1)
    }

    // MARK: - Search

    @Test("Search finds entities by name")
    @MainActor
    func searchByName() async {
        let service = FakeGraphKnowledgeService()
        service.entities = [
            "actor.alice": makeEntity(type: "actor", id: "alice", name: "Alice"),
            "thing.phone": makeEntity(type: "thing", id: "phone", name: "Phone"),
        ]

        let vm = KnowledgeGraphViewModel(knowledgeService: service, agentID: nil)
        await vm.search(query: "Ali")

        #expect(vm.searchResults.count == 1)
        #expect(vm.searchResults.first?.id == "actor.alice")
    }

    @Test("Empty search clears results")
    @MainActor
    func clearSearch() async {
        let service = FakeGraphKnowledgeService()
        service.entities = [
            "actor.alice": makeEntity(type: "actor", id: "alice", name: "Alice"),
        ]

        let vm = KnowledgeGraphViewModel(knowledgeService: service, agentID: nil)
        await vm.search(query: "Alice")
        #expect(!vm.searchResults.isEmpty)

        await vm.search(query: "")
        #expect(vm.searchResults.isEmpty)
    }

    // MARK: - Empty Graph

    @Test("Empty knowledge service produces empty graph")
    @MainActor
    func emptyKnowledge() async {
        let service = FakeGraphKnowledgeService()
        let vm = KnowledgeGraphViewModel(knowledgeService: service, agentID: nil)
        await vm.loadInitialGraph()

        #expect(vm.nodes.isEmpty)
        #expect(vm.edges.isEmpty)
        #expect(vm.focusID == nil)
        #expect(!vm.isLoading)
    }
}
