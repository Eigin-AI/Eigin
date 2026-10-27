@testable import Eigin
import Foundation
import Testing

@Suite("Knowledge details")
@MainActor
struct KnowledgeDetailsTests {
    @Test func loadsBothDirectionsOnceAndKeepsStoredPredicates() async {
        let service = FakeKnowledgeService()
        let focus = FirmEntity(id: "fact.v1.with.dots", entityType: "fact", fields: [
            .init(name: "uses", value: .list(items: [.entityReference(entityId: "thing.train")])),
        ])
        let train = FirmEntity(id: "thing.train", entityType: "thing", fields: [
            .init(name: "describes", value: .entityReference(entityId: focus.id)),
        ])
        service.relatedOutgoing[focus.id] = [train, train]
        service.relatedIncoming[focus.id] = [train]
        let agentID = UUID()
        let details = KnowledgeDetails(entity: focus, service: service, agentID: agentID)
        await details.load()
        #expect(service.relatedRequests.count == 1)
        #expect(service.relatedRequests.first?.0 == focus.id)
        #expect(service.relatedRequests.first?.1 == .both)
        #expect(details.relationships.count == 2)
        #expect(details.relationships.contains { $0.predicate == "uses" && !$0.incoming })
        #expect(details.relationships.contains { $0.predicate == "describes" && $0.incoming })
        #expect(service.receivedAgentIDs.allSatisfy { $0 == agentID })
    }

    @Test func retiredRelatedEntityProducesNoRelationshipRow() async {
        let service = FakeKnowledgeService()
        let focus = FirmEntity(id: "fact.current", entityType: "fact", fields: [
            .init(
                name: "supersedes",
                value: .list(items: [.entityReference(entityId: "fact.old")])
            ),
        ])
        let retired = FirmEntity(id: "fact.old", entityType: "fact", fields: [
            .init(name: "relates_to", value: .entityReference(entityId: focus.id)),
        ])
        service.relatedOutgoing[focus.id] = [retired]
        service.retiredIDs = [retired.id]
        let details = KnowledgeDetails(entity: focus, service: service, agentID: nil)
        await details.load()
        #expect(details.relationships.isEmpty)
    }

    @Test func failedDeletionLeavesKnowledgeAvailable() async {
        let service = FakeKnowledgeService()
        let entity = FirmEntity(id: "note.unsaved", entityType: "note", fields: [])
        service.entities[entity.id] = entity
        service.throwOnDeleteEntity = true
        let details = KnowledgeDetails(entity: entity, service: service, agentID: nil)
        #expect(await !details.delete())
        #expect(service.entities[entity.id] != nil)
        #expect(!details.isDeleting)
        service.throwOnDeleteEntity = false
        #expect(await details.delete())
        #expect(service.entities[entity.id] == nil)
    }

    @Test func refreshFailureKeepsRelationshipsAndExposesRetry() async {
        let service = FakeKnowledgeService()
        let target = FirmEntity(id: "thing.train", entityType: "thing", fields: [])
        let entity = FirmEntity(id: "note.draft", entityType: "note", fields: [
            .init(name: "relates_to", value: .entityReference(entityId: target.id)),
        ])
        service.relatedOutgoing[entity.id] = [target]
        let details = KnowledgeDetails(entity: entity, service: service, agentID: nil)
        await details.load()
        service.throwOnGetRelated = true
        await details.load()
        #expect(details.relationshipError != nil)
        #expect(details.relationships.first?.entity.id == target.id)
        service.throwOnGetRelated = false
        await details.load()
        #expect(details.relationshipError == nil)
        #expect(details.relationships.count == 1)
    }

    @Test func relationshipFailureCanBeRetried() async {
        let service = FakeKnowledgeService()
        let entity = FirmEntity(id: "note.draft", entityType: "note", fields: [])
        service.throwOnGetRelated = true
        let details = KnowledgeDetails(entity: entity, service: service, agentID: nil)
        await details.load()
        #expect(details.relationshipError != nil)
        service.throwOnGetRelated = false
        await details.load()
        #expect(details.relationshipError == nil)
        #expect(details.relationships.isEmpty)
    }
}
