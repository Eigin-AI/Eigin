@testable import Eigin
import Foundation
import SwiftData
import Testing

@Suite("Background preparation")
@MainActor
struct PreparationTests {
    @Test(arguments: [false, true])
    func sourcedFindingsUseSaveTimeAndRefreshOnUpdate(includeLegacyTimestamp: Bool) async throws {
        let container = try ModelContainer(
            for: Schema(SchemaV15.models, version: SchemaV15.versionIdentifier),
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
            let legacyTimestamp = includeLegacyTimestamp
                ? ",\"observed_at\":\"2099-11-19T22:00:00Z\"" : ""
            return ToolCall(
                id: "save",
                type: "function",
                function: .init(name: "save_preparation", arguments: """
                {"id":"news","intent_ids":["\(intent
                    .id)"],"content":"\(
                    content
                )","sources":["https://example.com/news"]\(legacyTimestamp)}
                """)
            )
        }
        let beforeSave = Date.now
        let result = await tool.execute(call("A new finding"), agent: agent)
        #expect(!result.isError, "\(result.content)")
        var previous = try #require(try await knowledge.unexpiredEntities(
            type: "preparation", spaceID: space.id, agentID: agent.id
        ).first)
        let initialObservation = try #require(previous.fields.first { $0.name == "observed_at" })
        guard case .dateTime(let initialValue) = initialObservation.value else {
            Issue.record("Expected a saved timestamp")
            return
        }
        let initialTime = try #require(ISO8601DateFormatter().date(from: initialValue))
        #expect(initialTime >= beforeSave.addingTimeInterval(-60))
        #expect(initialTime <= Date.now)
        previous.fields.removeAll { $0.name == "observed_at" }
        previous.fields.append(FirmField(
            name: "observed_at", value: .dateTime(value: "2020-01-01T00:00:00Z")
        ))
        try await knowledge.addEntity(previous, spaceID: space.id, agentID: agent.id, chatID: nil)
        let beforeUpdate = Date.now
        let updated = await tool.execute(call("Rechecked finding"), agent: agent)
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
        let savedAt = try #require(ISO8601DateFormatter().date(from: value))
        // Knowledge timestamps are persisted at minute precision.
        #expect(savedAt >= beforeUpdate.addingTimeInterval(-60))
        #expect(savedAt <= Date.now)
        #expect(finding.fields.contains {
            $0.name == "content" && $0.value == .string(value: "Rechecked finding")
        })
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

    @Test(arguments: [
        "arguments",
        "id",
        "intent_ids",
        "content",
        "sources",
    ])
    func invalidArgumentsExplainHowToCorrectPreparation(field: String) async throws {
        let container = try ModelContainer(
            for: Schema(SchemaV15.models, version: SchemaV15.versionIdentifier),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let agent = Agent(name: "Test", providerID: UUID(), model: "test")
        let intent = Intent(agentID: agent.id, content: "News")
        container.mainContext.insert(agent)
        container.mainContext.insert(intent)
        try container.mainContext.save()
        let tool = SavePreparationTool(
            modelContainer: container,
            knowledgeService: DefaultKnowledgeService(modelContainer: container),
            accessPolicy: SpaceAccessPolicy(currentSpaceID: nil, publicSpaceIDs: [])
        )
        var args: [String: Any] = [
            "id": "danish_newscast_2026_11_20",
            "intent_ids": [intent.id.uuidString],
            "content": "Sourced news summary",
            "sources": ["https://www.dr.dk/nyheder"],
        ]
        let expected: String
        switch field {
        case "id":
            args[field] = "Invalid ID"
            expected = "id must be 1–100 lowercase letters, digits or underscores, starting with a letter."
        case "intent_ids":
            args[field] = ["invalid-uuid"]
            expected = "intent_ids must contain 1–10 valid intent UUIDs."
        case "content":
            args[field] = ""
            expected = "content must be a nonempty string of at most 6000 characters."
        case "sources":
            args[field] = [""]
            expected = "sources must contain 1–20 nonempty source URLs or provider item identifiers, each at most 2000 characters."
        default:
            expected = "Provide save_preparation arguments as a JSON object."
        }
        let arguments = try field == "arguments" ? "{" : String(
            decoding: JSONSerialization.data(withJSONObject: args), as: UTF8.self
        )
        let result = await tool.execute(ToolCall(
            id: "save", type: "function",
            function: .init(name: "save_preparation", arguments: arguments)
        ), agent: agent)
        #expect(result.isError)
        let output = try #require(ToolHelpers.parseArguments(result.content))
        #expect(output["errors"] as? [String] == [expected])
        #expect(try container.mainContext.fetchCount(FetchDescriptor<FirmSource>()) == 0)
    }

    @Test func privateIntentsCannotBePreparedOutsideTheirSpace() async throws {
        let container = try ModelContainer(
            for: Schema(SchemaV15.models, version: SchemaV15.versionIdentifier),
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
                    .id)"],"content":"Secret","sources":["mail:123"]}
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
