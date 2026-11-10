@testable import Eigin
import Foundation
import SwiftData
import Testing

@Suite("Intent tools", .serialized)
struct IntentToolTests {
    // MARK: - Helpers

    @MainActor
    private func makeFixture() throws -> (Agent, DefaultIntentService) {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Schema(SchemaV2.models, version: SchemaV2.versionIdentifier),
            configurations: config
        )
        let agent = Agent(name: "TestAgent", providerID: UUID(), model: "test-model")
        container.mainContext.insert(agent)
        return (agent, DefaultIntentService(modelContainer: container))
    }

    private func makeCall(name: String, arguments: String) -> ToolCall {
        ToolCall(
            id: "call_\(name)",
            type: "function",
            function: .init(name: name, arguments: arguments)
        )
    }

    private let policy = SpaceAccessPolicy(currentSpaceID: nil, publicSpaceIDs: [])

    private func envelope(_ result: ToolResult) throws -> [String: Any] {
        try #require(JSONSerialization
            .jsonObject(with: Data(result.content.utf8)) as? [String: Any])
    }

    enum ScheduleInput: CaseIterable {
        case omitted, empty, daily

        var arguments: String {
            switch self {
            case .omitted: ""
            case .empty: #", "schedules": []"#
            case .daily: #", "schedules": [{"content": "Inbox overview", "frequency": "daily", "hour": 8}]"#
            }
        }
    }

    @Test(arguments: ["add_intent", "update_intent"], ScheduleInput.allCases)
    @MainActor func scheduleResponseMatchesSavedIntent(
        name: String,
        input: ScheduleInput
    ) async throws {
        let (agent, service) = try makeFixture()
        let id = try await service.create(
            content: "Inbox overview", agentID: agent.id, spaceID: nil, chatID: nil,
            tasks: [], events: [], schedules: []
        )
        let call = makeCall(name: name, arguments: """
        {"id": "\(id.uuidString)", "content": "Inbox overview"\(input.arguments)}
        """)
        let result = if name == "add_intent" {
            await AddIntentTool(intentService: service).execute(call, agent: agent)
        } else {
            await UpdateIntentTool(intentService: service).execute(call, agent: agent)
        }
        #expect(!result.isError)
        let response = try #require(envelope(result)["result"] as? [String: Any])
        let returnedID = try #require(response["id"] as? String)
        #expect(response["action"] as? String == (name == "add_intent" ? "created" : "updated"))
        if name == "update_intent" {
            #expect(returnedID == id.uuidString)
        }
        let intents = try await service.activeIntents(
            agentID: agent.id, limit: 10, accessPolicy: policy
        )
        let saved = try #require(intents.first { $0.id.uuidString == returnedID })
        #expect(saved.schedules.count == (input == .daily ? 1 : 0))
        if input == .daily {
            let guidance = try #require(response["guidance"] as? String)
            #expect(!guidance.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            let schedules = try #require(response["schedules"] as? [[String: String]])
            #expect(schedules.count == saved.schedules.count)
            let schedule = try #require(saved.schedules.first)
            #expect(schedules.first?["id"] == schedule.id.uuidString)
            #expect(schedules.first?["content"] == schedule.content)
            #expect(schedule.frequency == .daily)
            #expect(schedule.hour == 8)
        } else {
            #expect(response["guidance"] == nil)
            if name == "add_intent" || input == .empty {
                let schedules = try #require(response["schedules"] as? [[String: String]])
                #expect(schedules.isEmpty)
            } else {
                #expect(response["schedules"] == nil)
            }
        }
    }

    @Test @MainActor func clearingSchedulesOmitsGuidance() async throws {
        let (agent, service) = try makeFixture()
        let id = try await service.create(
            content: "Inbox overview", agentID: agent.id, spaceID: nil, chatID: nil,
            tasks: [], events: [],
            schedules: [IntentSchedule(content: "Inbox overview", frequency: .daily, hour: 8)]
        )
        let result = await UpdateIntentTool(intentService: service).execute(
            makeCall(name: "update_intent", arguments: """
            {"id": "\(id.uuidString)", "schedules": []}
            """), agent: agent
        )
        #expect(!result.isError)
        let response = try #require(envelope(result)["result"] as? [String: Any])
        #expect(response["guidance"] == nil)
        let schedules = try #require(response["schedules"] as? [[String: String]])
        #expect(schedules.isEmpty)
        let intents = try await service.activeIntents(
            agentID: agent.id, limit: 10, accessPolicy: policy
        )
        let intent = try #require(intents.first)
        #expect(intent.schedules.isEmpty)
    }

    @Test(arguments: ["add_intent", "update_intent"])
    @MainActor func rejectedSchedulesOmitGuidance(name: String) async throws {
        let (agent, service) = try makeFixture()
        let call = makeCall(name: name, arguments: """
        {"id": "\(UUID().uuidString)", "content": "Inbox overview",
         "schedules": [{"content": "Inbox overview", "frequency": "invalid"}]}
        """)
        let result = if name == "add_intent" {
            await AddIntentTool(intentService: service).execute(call, agent: agent)
        } else {
            await UpdateIntentTool(intentService: service).execute(call, agent: agent)
        }
        #expect(result.isError)
        let response = try envelope(result)
        #expect(response["result"] == nil)
        let errors = try #require(response["errors"] as? [String])
        #expect(!errors.isEmpty)
    }

    // MARK: - add_intent

    @Test @MainActor func addIntentCreatesWithSubObjects() async throws {
        let (agent, service) = try makeFixture()
        let tool = AddIntentTool(intentService: service)
        let call = makeCall(name: "add_intent", arguments: """
        {
          "content": "Help ship the alpha",
          "tasks": [{"content": "Finalize onboarding", "due": "2026-05-20", "priority": "high"}],
          "events": [{"content": "Launch", "at": "2026-05-25 09:00"}],
          "schedules": [{"content": "Check in", "frequency": "weekly", "weekdays": [2], "hour": 9}]
        }
        """)

        let result = await tool.execute(call, agent: agent)
        #expect(!result.isError)
        let response = try #require(envelope(result)["result"] as? [String: Any])
        #expect(response["action"] as? String == "created")

        let intents = try await service.activeIntents(
            agentID: agent.id,
            limit: 10,
            accessPolicy: policy
        )
        let intent = try #require(intents.first)
        #expect(intent.content == "Help ship the alpha")
        #expect(intent.tasks.count == 1)
        #expect(intent.tasks.first?.priority == .high)
        #expect(intent.events.count == 1)
        #expect(intent.schedules.first?.frequency == .weekly)
    }

    @Test @MainActor func addIntentRequiresContent() async throws {
        let (agent, service) = try makeFixture()
        let tool = AddIntentTool(intentService: service)
        let result = await tool.execute(makeCall(name: "add_intent", arguments: "{}"), agent: agent)
        #expect(result.isError)
    }

    @Test @MainActor func addIntentRejectsMalformedTask() async throws {
        let (agent, service) = try makeFixture()
        let tool = AddIntentTool(intentService: service)
        // Task without content is malformed.
        let call = makeCall(name: "add_intent", arguments: """
        {"content": "Goal", "tasks": [{"due": "2026-05-20"}]}
        """)
        let result = await tool.execute(call, agent: agent)
        #expect(result.isError)

        let intents = try await service.activeIntents(
            agentID: agent.id,
            limit: 10,
            accessPolicy: policy
        )
        #expect(intents.isEmpty) // nothing persisted on rejection
    }

    // MARK: - update_intent

    @Test @MainActor func updateIntentCompletesTask() async throws {
        let (agent, service) = try makeFixture()
        let task = IntentTask(content: "do thing")
        let id = try await service.create(
            content: "Goal", agentID: agent.id, spaceID: nil, chatID: nil,
            tasks: [task], events: [], schedules: []
        )

        let tool = UpdateIntentTool(intentService: service)
        // Full-replacement: resend the task with the same id, now completed.
        let call = makeCall(name: "update_intent", arguments: """
        {"id": "\(id.uuidString)", "tasks": [{"id": "\(task.id
            .uuidString)", "content": "do thing", "completed": true}]}
        """)
        let result = await tool.execute(call, agent: agent)
        #expect(!result.isError)

        let intents = try await service.activeIntents(
            agentID: agent.id,
            limit: 10,
            accessPolicy: policy
        )
        let updated = try #require(intents.first)
        #expect(updated.tasks.first?.completed == true)
        #expect(updated.tasks.first?.id == task.id) // identity preserved
    }

    @Test @MainActor func updateIntentLeavesUnspecifiedFieldsUntouched() async throws {
        let (agent, service) = try makeFixture()
        let id = try await service.create(
            content: "Goal", agentID: agent.id, spaceID: nil, chatID: nil,
            tasks: [IntentTask(content: "keep me")], events: [], schedules: []
        )

        let tool = UpdateIntentTool(intentService: service)
        let call = makeCall(name: "update_intent", arguments: """
        {"id": "\(id.uuidString)", "content": "Goal, revised"}
        """)
        _ = await tool.execute(call, agent: agent)

        let intents = try await service.activeIntents(
            agentID: agent.id,
            limit: 10,
            accessPolicy: policy
        )
        let updated = try #require(intents.first)
        #expect(updated.content == "Goal, revised")
        #expect(updated.tasks.count == 1) // tasks left intact
    }
}
