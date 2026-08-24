@testable import Eigin
import Foundation
import Testing

/// Behaviour of the memory-reconciliation tools: forget, supersede, merge.
@Suite("Knowledge memory tools")
@MainActor
struct KnowledgeMemoryToolsTests {
    private func agent() -> Agent {
        Agent(name: "TestAgent", providerID: UUID(), model: "test-model")
    }

    private func call(_ name: String, _ arguments: String) -> ToolCall {
        ToolCall(
            id: "call_\(name)",
            type: "function",
            function: .init(name: name, arguments: arguments)
        )
    }

    private func entity(_ type: String, _ id: String) -> FirmEntity {
        FirmEntity(id: "\(type).\(id)", entityType: type, fields: [])
    }

    private func supersedes(_ entity: FirmEntity) -> [String] {
        guard let field = entity.fields.first(where: { $0.name == "supersedes" }),
              case .list(let items) = field.value else { return [] }
        return items.compactMap { if case .entityReference(let id) = $0 { id } else { nil } }
    }

    // MARK: - forget

    @Test func forgetHidesEntry() async throws {
        let service = FakeKnowledgeService()
        service.entities["fact.likes_espresso"] = entity("fact", "likes_espresso")
        let tool = ForgetKnowledgeTool(knowledgeService: service, spaceID: nil, agentID: nil)

        let result = await tool.execute(
            call("forget_knowledge", #"{"type":"fact","id":"likes_espresso"}"#), agent: agent()
        )

        #expect(!result.isError)
        #expect(result.content.contains("forgotten"))
        #expect(service.expiredIDs.contains("fact.likes_espresso"))
        let visible = try await service.unexpiredEntities(type: "fact", spaceID: nil, agentID: nil)
        #expect(!visible.contains { $0.id == "fact.likes_espresso" })
    }

    @Test func forgetStripsTypePrefixFromID() async {
        let service = FakeKnowledgeService()
        service.entities["fact.old"] = entity("fact", "old")
        let tool = ForgetKnowledgeTool(knowledgeService: service, spaceID: nil, agentID: nil)

        let result = await tool.execute(
            call("forget_knowledge", #"{"type":"fact","id":"fact.old"}"#), agent: agent()
        )

        #expect(!result.isError)
        #expect(service.expiredIDs.contains("fact.old"))
    }

    // MARK: - supersede

    @Test func supersedeExpiresOldAndLinksNew() async throws {
        let service = FakeKnowledgeService()
        service.entities["fact.old_role"] = entity("fact", "old_role")
        service.entities["fact.new_role"] = entity("fact", "new_role")
        let tool = SupersedeKnowledgeTool(
            knowledgeService: service, spaceID: nil, agentID: nil, chatID: nil
        )

        let result = await tool.execute(
            call("supersede_knowledge", #"{"old":"fact.old_role","new":"fact.new_role"}"#),
            agent: agent()
        )

        #expect(!result.isError)
        #expect(service.expiredIDs.contains("fact.old_role"))
        #expect(!service.expiredIDs.contains("fact.new_role"))
        #expect(try supersedes(#require(service.entities["fact.new_role"])) == ["fact.old_role"])
    }

    @Test func supersedeRejectsMalformedIDs() async {
        let service = FakeKnowledgeService()
        service.entities["fact.new_role"] = entity("fact", "new_role")
        let tool = SupersedeKnowledgeTool(
            knowledgeService: service, spaceID: nil, agentID: nil, chatID: nil
        )

        let result = await tool.execute(
            call("supersede_knowledge", #"{"old":"not_qualified","new":"fact.new_role"}"#),
            agent: agent()
        )

        #expect(result.isError)
        #expect(service.expiredIDs.isEmpty)
    }

    // MARK: - merge

    @Test func mergeFoldsDuplicatesIntoSurvivor() async throws {
        let service = FakeKnowledgeService()
        service.entities["thing.eigin"] = entity("thing", "eigin")
        service.entities["thing.eigin_app"] = entity("thing", "eigin_app")
        service.entities["thing.eigin_dup"] = entity("thing", "eigin_dup")
        let tool = MergeKnowledgeTool(
            knowledgeService: service, spaceID: nil, agentID: nil, chatID: nil
        )

        let result = await tool.execute(
            call(
                "merge_knowledge",
                #"{"into":"thing.eigin","from":["thing.eigin_app","thing.eigin_dup"]}"#
            ),
            agent: agent()
        )

        #expect(!result.isError)
        #expect(service.expiredIDs.contains("thing.eigin_app"))
        #expect(service.expiredIDs.contains("thing.eigin_dup"))
        #expect(!service.expiredIDs.contains("thing.eigin"))
        #expect(
            try Set(supersedes(#require(service.entities["thing.eigin"])))
                == ["thing.eigin_app", "thing.eigin_dup"]
        )
    }

    // MARK: - importance

    @Test func addSetsImportanceWhenProvided() async {
        let service = FakeKnowledgeService()
        let tool = AddKnowledgeTool(
            knowledgeService: service, spaceID: nil, agentID: nil, chatID: nil
        )

        let result = await tool.execute(
            call(
                "add_knowledge",
                #"{"type":"fact","id":"penicillin_allergy","data":{"name":"Penicillin allergy"},"importance":0.95}"#
            ), agent: agent()
        )

        #expect(!result.isError)
        #expect(service.importanceByID["fact.penicillin_allergy"] == 0.95)
    }

    @Test func addLeavesImportanceUnsetWhenOmitted() async {
        let service = FakeKnowledgeService()
        let tool = AddKnowledgeTool(
            knowledgeService: service, spaceID: nil, agentID: nil, chatID: nil
        )

        _ = await tool.execute(
            call("add_knowledge", #"{"type":"note","id":"trivia","data":{"content":"x"}}"#),
            agent: agent()
        )

        #expect(service.importanceByID["note.trivia"] == nil)
    }

    @Test func updateSetsImportance() async {
        let service = FakeKnowledgeService()
        service.entities["fact.deadline"] = entity("fact", "deadline")
        let tool = UpdateKnowledgeTool(
            knowledgeService: service, spaceID: nil, agentID: nil, chatID: nil
        )

        let result = await tool.execute(
            call(
                "update_knowledge",
                #"{"type":"fact","id":"deadline","data":{"name":"Tax deadline"},"importance":0.9}"#
            ), agent: agent()
        )

        #expect(!result.isError)
        #expect(service.importanceByID["fact.deadline"] == 0.9)
    }

    // MARK: - contest

    @Test func contestFlagsConflictingEntries() async {
        let service = FakeKnowledgeService()
        service.entities["fact.a"] = entity("fact", "a")
        service.entities["fact.b"] = entity("fact", "b")
        let tool = ContestKnowledgeTool(knowledgeService: service, spaceID: nil, agentID: nil)

        let result = await tool.execute(
            call("contest_knowledge", #"{"ids":["fact.a","fact.b"]}"#), agent: agent()
        )

        #expect(!result.isError)
        #expect(service.contestedIDs == ["fact.a", "fact.b"])
    }

    @Test func contestRejectsFewerThanTwo() async {
        let service = FakeKnowledgeService()
        service.entities["fact.a"] = entity("fact", "a")
        let tool = ContestKnowledgeTool(knowledgeService: service, spaceID: nil, agentID: nil)

        let result = await tool.execute(
            call("contest_knowledge", #"{"ids":["fact.a"]}"#), agent: agent()
        )

        #expect(result.isError)
        #expect(service.contestedIDs.isEmpty)
    }

    @Test func mergeIgnoresSurvivorListedInFrom() async {
        let service = FakeKnowledgeService()
        service.entities["thing.eigin"] = entity("thing", "eigin")
        let tool = MergeKnowledgeTool(
            knowledgeService: service, spaceID: nil, agentID: nil, chatID: nil
        )

        let result = await tool.execute(
            call("merge_knowledge", #"{"into":"thing.eigin","from":["thing.eigin"]}"#),
            agent: agent()
        )

        // Nothing to merge once the survivor is filtered out.
        #expect(result.isError)
        #expect(service.expiredIDs.isEmpty)
    }
}
