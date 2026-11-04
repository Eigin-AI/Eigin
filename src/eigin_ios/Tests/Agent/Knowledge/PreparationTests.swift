@testable import Eigin
import Foundation
import SwiftData
import Testing

@Suite("Background preparation")
@MainActor
struct PreparationTests {
    @Test func sourcedFindingsPersistInIntentScopeAndKeepObservationTime() async throws {
        let container = try ModelContainer(
            for: Schema(SchemaV11.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let agent = Agent(name: "Test", providerID: UUID(), model: "test")
        context.insert(agent)
        let space = Space(agentID: agent.id)
        context.insert(space)
        let intent = Intent(agentID: agent.id, content: "News", spaceID: space.id)
        context.insert(intent)
        try context.save()
        let knowledge = DefaultKnowledgeService(modelContainer: container)
        let tool = SavePreparationTool(
            modelContainer: container,
            knowledgeService: knowledge,
            accessPolicy: SpaceAccessPolicy(currentSpaceID: space.id, publicSpaceIDs: [])
        )
        func call(_ content: String) -> ToolCall {
            ToolCall(
                id: "save",
                type: "function",
                function: .init(name: "save_preparation", arguments: """
                {"id":"news","intent_ids":["\(intent
                    .id)"],"content":"\(
                    content
                )","sources":["https://example.com/news"],"observed_at":"2026-10-01T07:00:00Z"}
                """)
            )
        }
        let result = await tool.execute(call("A new finding"), agent: agent)
        #expect(!result.isError, "\(result.content)")
        let updated = await tool.execute(call("Clarified wording"), agent: agent)
        #expect(!updated.isError, "\(updated.content)")
        let findings = try await knowledge.unexpiredEntities(
            type: "preparation",
            spaceID: space.id,
            agentID: agent.id
        )
        #expect(findings.count == 1)
        let finding = try #require(findings.first)
        let observed = try #require(finding.fields.first { $0.name == "observed_at" })
        guard case .dateTime(let value) = observed.value
        else { Issue.record("Expected dateTime, got \(observed.value)"); return }
        #expect(ISO8601DateFormatter().date(from: value) == ISO8601DateFormatter()
            .date(from: "2026-10-01T07:00:00Z"))
        #expect(finding.fields
            .contains {
                $0.name == "sources" && $0
                    .value == .list(items: [.string(value: "https://example.com/news")])
            })
        let stored = try context.fetch(FetchDescriptor<FirmSource>())
        #expect(stored.count == 1)
        #expect(stored.first?.spaceID == space.id)
        #expect(stored.first?.agentID == agent.id)
    }

    @Test func privateIntentsCannotBePreparedOutsideTheirSpace() async throws {
        let container = try ModelContainer(
            for: Schema(SchemaV11.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let agent = Agent(name: "Test", providerID: UUID(), model: "test")
        let intent = Intent(agentID: agent.id, content: "Private", spaceID: UUID())
        container.mainContext.insert(agent)
        container.mainContext.insert(intent)
        try container.mainContext.save()
        let tool = SavePreparationTool(
            modelContainer: container,
            knowledgeService: DefaultKnowledgeService(modelContainer: container),
            accessPolicy: SpaceAccessPolicy(currentSpaceID: nil, publicSpaceIDs: [])
        )
        let result = await tool.execute(
            ToolCall(
                id: "save",
                type: "function",
                function: .init(name: "save_preparation", arguments: """
                {"id":"private","intent_ids":["\(intent
                    .id)"],"content":"Secret","sources":["mail:123"],"observed_at":"2026-10-01T07:00:00Z"}
                """)
            ),
            agent: agent
        )
        #expect(result.isError)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<FirmSource>()) == 0)
    }

    @Test func preparationRegistryExposesReadsAndIncrementalSavingOnly() {
        let registry = ToolRegistry.background(preparationOnly: true, onSignal: { _ in })
        let names = Set(registry.definitions.map(\.function.name))
        #expect(names.contains("save_preparation"))
        #expect(names.contains("list_intents"))
        #expect(names.contains("list_initiatives"))
        for name in [
            "background_notify",
            "follow_up",
            "email_send",
            "email_reply",
            "create_calendar_event",
            "set_initiatives",
            "cancel_initiative",
            "add_knowledge",
            "update_knowledge",
        ] {
            #expect(!names.contains(name))
        }
        #expect(names.allSatisfy(PreparationToolPolicy.allows))
    }
}
