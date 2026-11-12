@testable import Eigin
import Factory
import Foundation
import SwiftData
import Testing
import UserNotifications

@Suite("Initiative tools", .serialized)
@MainActor
struct InitiativeToolsTests {
    @Test func splitToolsListAndCancelWithoutNotificationPermission() async throws {
        let container = try ModelContainer(
            for: Schema(SchemaV15.models, version: SchemaV15.versionIdentifier),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let agent = Agent(name: "Test", providerID: UUID(), model: "test")
        let schedule = IntentSchedule(content: "News", frequency: .daily, hour: 7, minute: 0)
        let intent = Intent(agentID: agent.id, content: "News", schedules: [schedule])
        container.mainContext.insert(agent)
        container.mainContext.insert(intent)
        try container.mainContext.save()
        let notifications = FakeInitiativeNotifications()
        @MainActor func service(_ status: UNAuthorizationStatus) -> InitiativeService {
            InitiativeService(
                modelContainer: container,
                scheduler: InitiativeNotificationScheduler(
                    notifications: notifications,
                    authorization: FakeNotificationAuthorization(status: status),
                    contentPreparer: FakeCommunicationNotificationPreparer()
                )
            )
        }
        let enabled = service(.authorized)
        let set = SetInitiativesTool(service: enabled, spaceID: nil, canPromptUser: true)
        let created = await set.execute(call("set_initiatives", """
        {"changes":[{"intent_id":"\(intent.id)","schedule_id":"\(schedule
            .id)","instructions":"Get news","notification":"News update"}]}
        """), agent: agent)
        #expect(!created.isError)
        let denied = service(.denied)
        let registry = ToolRegistry(tools: [
            ListInitiativesTool(service: denied, spaceID: nil),
            CancelInitiativeTool(service: denied, spaceID: nil),
        ])
        let listed = await registry.execute(call("list_initiatives", "{}"), agent: agent)
        #expect(!listed.isError)
        let agreements = try #require(result(listed)["initiatives"] as? [[String: Any]])
        let id = try #require(agreements.first?["id"] as? String)
        let wrongScopeCancel = await CancelInitiativeTool(service: denied, spaceID: UUID()).execute(
            call("cancel_initiative", "{\"id\":\"\(id)\"}"),
            agent: agent
        )
        #expect(wrongScopeCancel.isError)
        #expect(notifications.requests.count == 1)
        let invalid = await registry.execute(
            call("cancel_initiative", #"{"id":"news"}"#),
            agent: agent
        )
        #expect(invalid.isError)
        #expect(try result(invalid)["status"] as? String == "invalid_initiative_id")
        #expect(notifications.requests.count == 1)
        let cancelled = await registry.execute(
            call("cancel_initiative", "{\"id\":\"\(id)\"}"),
            agent: agent
        )
        #expect(!cancelled.isError)
        #expect(notifications.requests.isEmpty)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Intent>()) == 1)
        let after = await registry.execute(call("list_initiatives", "{}"), agent: agent)
        let remaining = try #require(result(after)["initiatives"] as? [[String: Any]])
        #expect(remaining.first?["enabled"] as? Bool == false)
        let wrongScope = ListInitiativesTool(service: denied, spaceID: UUID())
        let scoped = await wrongScope.execute(call("list_initiatives", "{}"), agent: agent)
        #expect(try (result(scoped)["initiatives"] as? [[String: Any]])?.isEmpty == true)
    }

    @Test func splitToolsRetainExistingGrantsAndSkillGating() {
        Container.shared.reset()
        for level in [ToolPermissionLevel.never, .ask, .always] {
            let policy = AgentPermissionPolicy(
                builtInGrants: ["set_intent_initiatives": level],
                discoveredGrants: [:],
                chatGrants: [],
                canPromptUser: true
            )
            for name in ["list_initiatives", "set_initiatives", "cancel_initiative"] {
                #expect(policy.permissionLevel(for: name) == level)
            }
            let registry = ToolRegistry.chat(
                permissionPolicy: policy,
                activeSkills: [BundledSkill.intents]
            )
            let definitions = registry.definitions
            let names = Set(definitions.map(\.function.name))
            let expected: Set = ["list_initiatives", "set_initiatives", "cancel_initiative"]
            #expect(names.isDisjoint(with: expected) == (level == .never))
            if level != .never {
                #expect(expected.isSubset(of: names))
                #expect(definitions.first { $0.function.name == "list_initiatives" }?.function
                    .parameters.properties?.isEmpty == true)
                #expect(definitions.first { $0.function.name == "set_initiatives" }?.function
                    .parameters.required == ["changes"])
                #expect(definitions.first { $0.function.name == "cancel_initiative" }?.function
                    .parameters.required == ["id"])
                #expect(definitions.filter { expected.contains($0.function.name) }
                    .allSatisfy { $0.function.parameters.properties?["action"] == nil })
            }
            #expect(!names.contains("set_intent_initiatives"))
        }
        let otherSkill = ToolRegistry.chat(
            permissionPolicy: AlwaysAllowPolicy(),
            activeSkills: [BundledSkill.web]
        )
        #expect(!otherSkill.definitions
            .contains { IntentToolKit.initiativeToolNames.contains($0.function.name) })
    }

    private func call(_ name: String, _ arguments: String) -> ToolCall {
        ToolCall(id: "test", type: "function", function: .init(name: name, arguments: arguments))
    }

    private func result(_ response: ToolResult) throws -> [String: Any] {
        let envelope = try #require(ToolHelpers.parseArguments(response.content))
        return try #require(envelope["result"] as? [String: Any])
    }
}
