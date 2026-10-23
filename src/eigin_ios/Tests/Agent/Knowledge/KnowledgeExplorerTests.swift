@testable import Eigin
import Foundation
import Testing

@Suite("Bounded knowledge explorer")
@MainActor
struct KnowledgeExplorerTests {
    private func entity(_ id: String, fields: [FirmField] = []) -> FirmEntity {
        FirmEntity(id: id, entityType: String(id.split(separator: ".")[0]), fields: fields)
    }

    @Test func summaryTrimsLongContentAndPreservesShortContent() {
        let long = String(repeating: "A", count: 200)
        let presentation = KnowledgePresentation(entity("note.long", fields: [
            FirmField(name: "content", value: .string(value: long)),
        ]))
        #expect(presentation.summary == String(long.prefix(139)) + "…")
        #expect(presentation.content == long)
        let short = KnowledgePresentation(entity("note.short", fields: [
            FirmField(name: "content", value: .string(value: "A short note.")),
        ]))
        #expect(short.summary == "A short note.")
        #expect(KnowledgePresentation(entity("actor.user")).summary == nil)
    }

    @Test func connectionRangeFormatsCountsAsText() {
        let formatted = Localized.Knowledge.Graph.connectionRange("7", "12", "18")
        #expect(formatted.contains("7–12"))
        #expect(formatted.contains("18"))
    }

    @Test func paginationPinsArrivalWithoutLosingNeighbors() async {
        let service = FakeKnowledgeService()
        let user = entity("actor.user")
        let hub = entity("thing.hub")
        let others = (0 ..< 14).map { entity("note.\($0)") }
        service.entities[user.id] = user
        service.relatedOutgoing["actor.user"] = [hub]
        service.relatedOutgoing["thing.hub"] = others + [user]
        service.relatedIncoming["thing.hub"] = [user, user]
        let explorer = KnowledgeExplorer(service: service, agentID: nil)
        await explorer.load()
        await explorer.focus(hub)
        #expect(explorer.visibleNeighbors.first?.id == user.id)
        #expect(explorer.pageCount == 3)
        var ids: [String] = []
        for page in 0 ..< explorer.pageCount {
            explorer.setPage(page)
            ids += explorer.visibleNeighbors.map(\.id)
        }
        #expect(ids.count == 15)
        #expect(Set(ids).count == 15)
        explorer.setCapacity(4)
        #expect(explorer.visibleNeighbors.count <= 4)
        await explorer.reset()
        #expect(explorer.neighborhood?.focus.id == user.id)
        #expect(explorer.arrivedFrom == nil)
        #expect(explorer.page == 0)
        #expect(service.relatedRequests.count == 2)
        #expect(service.relatedRequests.allSatisfy { $0.1 == .both })
    }

    @Test func staleRequestCannotReplaceLatestFocus() async {
        let service = FakeKnowledgeService()
        let user = entity("actor.user")
        let slow = entity("thing.slow")
        let fast = entity("thing.fast")
        service.entities[user.id] = user
        let explorer = KnowledgeExplorer(service: service, agentID: nil)
        await explorer.load()
        let gate = NeighborhoodGate()
        service.relatedOverride = { key in
            if key == "thing.slow" { return await gate.wait() }
            return [user]
        }
        let first = Task { await explorer.focus(slow) }
        while await !(gate.started) {
            await Task.yield()
        }
        await explorer.focus(fast)
        await gate.finish([user])
        await first.value
        #expect(explorer.neighborhood?.focus.id == fast.id)
        #expect(!explorer.isLoading)
        #expect(explorer.error == nil)
    }

    @Test func leavingScreenDiscardsSuspendedRequest() async {
        let service = FakeKnowledgeService()
        let user = entity("actor.user")
        service.entities[user.id] = user
        let explorer = KnowledgeExplorer(service: service, agentID: nil)
        await explorer.load()
        let gate = NeighborhoodGate()
        service.relatedOverride = { _ in await gate.wait() }
        let request = Task { await explorer.focus(entity("thing.later")) }
        while await !(gate.started) {
            await Task.yield()
        }
        explorer.cancel()
        await gate.finish([user])
        await request.value
        #expect(explorer.neighborhood?.focus.id == user.id)
        #expect(!explorer.isLoading)
        #expect(explorer.error == nil)
    }

    @Test func failedRefreshPreservesVisibleContent() async {
        let service = FakeKnowledgeService()
        let user = entity("actor.user")
        service.entities[user.id] = user
        let explorer = KnowledgeExplorer(service: service, agentID: nil)
        await explorer.load()
        service.throwOnGetRelated = true
        await explorer.refresh()
        #expect(explorer.neighborhood?.focus.id == user.id)
        #expect(explorer.error != nil)
        #expect(!explorer.isLoading)
    }

    @Test func refreshAfterDeletionFindsNewRoot() async {
        let service = FakeKnowledgeService()
        let user = entity("actor.user")
        let other = entity("thing.other")
        service.entities = [user.id: user, other.id: other]
        service.relatedOutgoing["actor.user"] = [other]
        let explorer = KnowledgeExplorer(service: service, agentID: nil)
        await explorer.load()
        await explorer.focus(other)
        service.entities.removeValue(forKey: other.id)
        service.relatedOutgoing["actor.user"] = []
        await explorer.refresh()
        #expect(explorer.neighborhood?.focus.id == user.id)
        #expect(explorer.visibleNeighbors.isEmpty)
        #expect(explorer.pageCount == 1)
    }

    @Test func absentUserFallsBackAndEmptyWorkspaceStaysEmpty() async {
        let service = FakeKnowledgeService()
        let explorer = KnowledgeExplorer(service: service, agentID: nil)
        await explorer.load()
        #expect(explorer.neighborhood == nil)
        #expect(!explorer.isLoading)
        let fallback = entity("note.first")
        service.entities[fallback.id] = fallback
        await explorer.load()
        #expect(explorer.root?.id == fallback.id)
        #expect(explorer.visibleNeighbors.isEmpty)
    }

    @Test func deletingRootWhileFocusedElsewhereRevalidatesHome() async throws {
        let service = FakeKnowledgeService()
        let user = entity("actor.user")
        let hub = entity("thing.hub")
        service.entities = [user.id: user, hub.id: hub]
        service.relatedOutgoing[user.id] = [hub]
        service.relatedOutgoing[hub.id] = [user]
        let explorer = KnowledgeExplorer(service: service, agentID: nil)
        await explorer.load()
        await explorer.focus(hub)
        try await service.deleteEntity(type: "actor", id: "user", spaceID: nil, agentID: nil)
        service.relatedOutgoing[hub.id] = []
        await explorer.refresh()
        #expect(explorer.neighborhood?.focus.id == hub.id)
        #expect(explorer.root?.id == hub.id)
        await explorer.reset()
        #expect(explorer.neighborhood?.focus.id == hub.id)
        #expect(explorer.arrivedFrom == nil)
        #expect(explorer.error == nil)
    }

    @Test func failedNavigationRetainsGraphAndRetryReachesRequestedNeighbor() async {
        let service = FakeKnowledgeService()
        let user = entity("actor.user")
        let hub = entity("thing.hub")
        service.entities = [user.id: user, hub.id: hub]
        service.relatedOutgoing[user.id] = [hub]
        let explorer = KnowledgeExplorer(service: service, agentID: nil)
        await explorer.load()
        service.throwOnGetRelated = true
        await explorer.focus(hub)
        #expect(explorer.error != nil)
        #expect(explorer.neighborhood?.focus.id == user.id)
        service.throwOnGetRelated = false
        await explorer.retry()
        #expect(explorer.neighborhood?.focus.id == hub.id)
        #expect(explorer.error == nil)
    }

    @Test func failedRefreshRetainsGraphAndRetryFetchesUpdatedContent() async {
        let service = FakeKnowledgeService()
        let user = entity("actor.user")
        let note = entity("note.new")
        service.entities = [user.id: user, note.id: note]
        let explorer = KnowledgeExplorer(service: service, agentID: nil)
        await explorer.load()
        service.throwOnGetRelated = true
        await explorer.refresh()
        #expect(explorer.error != nil)
        #expect(explorer.neighborhood?.focus.id == user.id)
        service.throwOnGetRelated = false
        service.relatedOutgoing[user.id] = [note]
        await explorer.retry()
        #expect(explorer.visibleNeighbors.map(\.id) == [note.id])
        #expect(explorer.error == nil)
    }

    @Test func resolvesPredicateDirectionAndQualifiedIdentity() async {
        let service = FakeKnowledgeService()
        let user = entity("actor.user", fields: [
            FirmField(
                name: "uses",
                value: .list(items: [.entityReference(entityId: "thing.same")])
            ),
            FirmField(
                name: "relates_to",
                value: .list(items: [.entityReference(entityId: "note.same")])
            ),
        ])
        let thing = entity("thing.same", fields: [
            FirmField(
                name: "describes",
                value: .list(items: [.entityReference(entityId: user.id)])
            ),
        ])
        let note = entity("note.same")
        service.entities[user.id] = user
        service.relatedOutgoing["actor.user"] = [thing, note, thing]
        let explorer = KnowledgeExplorer(service: service, agentID: nil)
        await explorer.load()
        let rows = explorer.neighborhood?.relationships ?? []
        #expect(rows.count == 3)
        #expect(rows
            .contains { $0.predicate == "uses" && !$0.incoming && $0.entity.id == thing.id })
        #expect(rows.contains { $0.predicate == "describes" && $0.incoming })
        #expect(rows.contains { $0.predicate == "relates_to" && $0.entity.id == note.id })
    }
}

private actor NeighborhoodGate {
    private var continuation: CheckedContinuation<[FirmEntity], Never>?
    var started: Bool {
        continuation != nil
    }

    func wait() async -> [FirmEntity] {
        await withCheckedContinuation { continuation = $0 }
    }

    func finish(_ entities: [FirmEntity]) {
        continuation?.resume(returning: entities)
        continuation = nil
    }
}
