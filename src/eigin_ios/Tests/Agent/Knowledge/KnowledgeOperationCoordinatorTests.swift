@testable import Eigin
import Foundation
import SwiftData
import Testing

@Suite("Background knowledge coordination")
@MainActor
struct KnowledgeOperationCoordinatorTests {
    @Test func cancelledWaiterReturnsBeforeHolderReleasesGate() async {
        let gate = KnowledgeOperationCoordinator()
        var release: CheckedContinuation<Void, Never>?
        let holder = Task { @MainActor in
            try await gate.perform { await withCheckedContinuation { release = $0 } }
        }
        while release == nil {
            await Task.yield()
        }
        var waiting = false
        let waiter = Task { @MainActor in
            waiting = true
            do {
                try await gate.perform { Issue.record("Cancelled waiter acquired the gate") }
                return false
            } catch is CancellationError { return true }
            catch { return false }
        }
        while !waiting {
            await Task.yield()
        }
        waiter.cancel()
        let timeout = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            release?.resume()
            release = nil
        }
        #expect(await waiter.value)
        #expect(release != nil)
        release?.resume()
        release = nil
        timeout.cancel()
        _ = try? await holder.value
    }

    @Test func concurrentContentAndReviewUpdatesBothSurvive() async throws {
        let container = try ModelContainer(
            for: Schema(SchemaV16.models, version: SchemaV16.versionIdentifier),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let service = DefaultKnowledgeService(modelContainer: container)
        func note(_ content: String) -> FirmEntity {
            FirmEntity(id: "note.background_test", entityType: "note", fields: [
                FirmField(name: "content", value: .string(value: content)),
                FirmField(name: "created_at", value: .dateTime(value: Date.now.ISO8601Format())),
            ])
        }
        try await service.addEntity(note("Before"), spaceID: nil, agentID: nil)
        let update = Task { @MainActor in
            try await KnowledgeOperationCoordinator.shared.perform {
                try await service.addEntity(note("After"), spaceID: nil, agentID: nil)
            }
        }
        let review = Task { @MainActor in
            try await KnowledgeOperationCoordinator.shared.perform {
                try await service.markReviewed(["note.background_test"], spaceID: nil, agentID: nil)
            }
        }
        try await update.value
        try await review.value
        let rows = try ModelContext(container).fetch(FetchDescriptor<FirmSource>())
        let row = try #require(rows.first { $0.path.contains("background_test") })
        #expect(row.content.contains("After"))
        #expect(row.lastReviewedAt != nil)
    }

    @Test func preparationRegistryAndMaintenanceUseSeparateKnowledgeSessions() async throws {
        let container = try ModelContainer(
            for: Schema(SchemaV16.models, version: SchemaV16.versionIdentifier),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let agent = Agent(name: "Test", providerID: UUID(), model: "test")
        let intent = Intent(agentID: agent.id, content: "News")
        container.mainContext.insert(agent)
        container.mainContext.insert(intent)
        try container.mainContext.save()
        let fixture = DefaultKnowledgeService(modelContainer: container)
        try await fixture.addEntity(
            FirmEntity(id: "note.stale_fixture", entityType: "note", fields: [
                FirmField(name: "content", value: .string(value: "Stale review candidate")),
                FirmField(name: "created_at", value: .dateTime(value: Date.now.ISO8601Format())),
            ]),
            spaceID: nil,
            agentID: nil
        )
        let seed = ModelContext(container)
        let stale = try #require(try seed.fetch(FetchDescriptor<FirmSource>())
            .first { $0.path.contains("stale_fixture") })
        stale.embedding = [1, 0]
        stale.lastAccessedAt = .distantPast
        stale.importance = 0
        try seed.save()
        let prep = DefaultKnowledgeService(modelContainer: container)
        let maintenance = DefaultKnowledgeService(modelContainer: container)
        let registry = ToolRegistry.background(
            agentID: agent.id, preparationOnly: true, knowledgeService: prep,
            modelContainer: container, onSignal: { _ in }
        )
        let call = ToolCall(
            id: "save",
            type: "function",
            function: .init(name: "save_preparation", arguments: """
            {"id":"news","intent_ids":["\(intent
                .id)"],"content":"Finding","sources":["https://example.com/news"]}
            """)
        )
        var release: CheckedContinuation<Void, Never>?
        let holder = Task { @MainActor in
            try await KnowledgeOperationCoordinator.shared.perform {
                await withCheckedContinuation { release = $0 }
            }
        }
        while release == nil {
            await Task.yield()
        }
        var attempted = 0
        var finished = 0
        let review = Task { @MainActor in
            attempted += 1
            let section = await BackgroundPromptService.knowledgeConsolidationSection(
                mode: .maintenance, knowledgeService: maintenance
            )
            finished += 1
            return section
        }
        let preparation = Task { @MainActor in
            attempted += 1
            let result = await registry.execute(call, agent: agent)
            finished += 1
            return result
        }
        while attempted < 2 {
            await Task.yield()
        }
        #expect(finished == 0)
        release?.resume()
        try await holder.value
        let result = await preparation.value
        #expect(!result.isError, "\(result.content)")
        #expect(await review.value.contains("note.stale_fixture"))
        let saved = try ModelContext(container).fetch(FetchDescriptor<FirmSource>())
        #expect(saved.contains { $0.agentID == agent.id && $0.content.contains("Finding") })
        #expect(saved.contains { $0.path.contains("stale_fixture") && $0.lastReviewedAt != nil })
    }
}
