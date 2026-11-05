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

    @Test(arguments: ["add_intent", "update_intent"], [
        "",
        #", "schedules": []"#,
        #", "schedules": [{"content": "Inbox overview", "frequency": "daily", "hour": 8}]"#,
    ])
    @MainActor func scheduleGuidance(name: String, scheduleArguments: String) async throws {
        let (agent, service) = try makeFixture()
        let id = try await service.create(
            content: "Inbox overview", agentID: agent.id, spaceID: nil, chatID: nil,
            tasks: [], events: [], schedules: []
        )
        let call = makeCall(name: name, arguments: """
        {"id": "\(id.uuidString)", "content": "Inbox overview"\(scheduleArguments)}
        """)
        let result = if name == "add_intent" {
            await AddIntentTool(intentService: service).execute(call, agent: agent)
        } else {
            await UpdateIntentTool(intentService: service).execute(call, agent: agent)
        }
        #expect(!result.isError)
        let hasSchedules = scheduleArguments.contains("daily")
        #expect(result.content.contains("guidance") == hasSchedules)
        #expect(result.content.contains("set_initiatives") == hasSchedules)
        if hasSchedules {
            #expect(result.content.contains("do not create notifications"))
            let intents = try await service.activeIntents(
                agentID: agent.id, limit: 10, accessPolicy: policy
            )
            let scheduledIntent = try #require(intents.first { !$0.schedules.isEmpty })
            let schedule = try #require(scheduledIntent.schedules.first)
            #expect(result.content.contains(scheduledIntent.id.uuidString))
            #expect(result.content.contains(schedule.id.uuidString))
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
        #expect(!result.content.contains("guidance"))
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
        #expect(!result.content.contains("guidance"))
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
        #expect(result.content.contains("created"))

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
