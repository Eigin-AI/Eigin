@testable import Eigin
import Foundation
import SwiftData
import Testing

@Suite("FollowUpTool")
struct FollowUpToolTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func call(time: String? = "2030-01-01T12:00:00Z") throws -> ToolCall {
        var args = [
            "notification_title": "Check in",
            "message": "Take a break",
            "summary": "User requested a break reminder.",
        ]
        args["deliver_at"] = time
        return try ToolCall(
            id: "follow",
            type: "function",
            function: .init(
                name: "follow_up",
                arguments: String(decoding: JSONEncoder().encode(args), as: UTF8.self)
            )
        )
    }

    @MainActor
    private func agent() -> Agent {
        Agent(name: "Test", providerID: UUID(), model: "test")
    }

    @Test(
        "Five-minute and nearby follow-ups return compact warnings",
        arguments: [-300.0, 300.0, 600.0]
    )
    @MainActor func warningEnvelope(gap: Double) async throws {
        let container = try ModelContainer(
            for: Schema(SchemaV15.models, version: SchemaV15.versionIdentifier),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let agent = agent()
        let proposed = try #require(ISO8601DateFormatter().date(from: "2030-01-01T12:00:00Z"))
        let existing = AgentInitiativeRequest(agentID: agent.id, message: "Existing")
        existing.dueAt = proposed.addingTimeInterval(gap)
        container.mainContext.insert(agent)
        container.mainContext.insert(existing)
        try container.mainContext.save()
        let scheduler = DefaultFollowUpScheduler(container: container, authorize: { _ in false })
        let tool = FollowUpTool(scheduler: scheduler)
        let result = try await tool.execute(call(), agent: agent)
        #expect(!result.isError)
        let envelope = try #require(JSONSerialization
            .jsonObject(with: Data(result.content.utf8)) as? [String: Any])
        let warnings = try #require(envelope["warnings"] as? [String])
        #expect(warnings.count == 1)
        let clock = DateFormatter()
        clock.timeStyle = .short
        #expect(warnings[0].contains(clock.string(from: proposed)))
        #expect(warnings[0].contains(clock.string(from: proposed.addingTimeInterval(gap))))
        #expect(!warnings[0].contains("2030-01-01T"))
        let payload = try #require(envelope["result"] as? [String: Any])
        #expect(payload["status"] as? String == "saved")
        #expect(payload["spacing_warnings"] == nil)
    }

    @Test("Reports saved follow-up and optional delivery outcome")
    @MainActor func schedules() async throws {
        let scheduler = FakeFollowUpScheduler()
        let instant = now
        let tool = FollowUpTool(scheduler: scheduler, now: { instant })
        let result = try await tool.execute(call(), agent: agent())
        #expect(!result.isError)
        #expect(scheduler.scheduledDates.count == 1)
        #expect(result.content.contains(scheduler.requestID.uuidString))
        #expect(result.content.contains("notification_scheduled"))
    }

    @Test(
        "Missing or invalid times fail before requesting authorization",
        arguments: [nil, "", "tomorrow", "2020-01-01T12:00:00Z"] as [String?]
    )
    @MainActor func invalidTime(time: String?) async throws {
        let scheduler = FakeFollowUpScheduler()
        let instant = now
        let tool = FollowUpTool(scheduler: scheduler, now: { instant })
        let result = try await tool.execute(call(time: time), agent: agent())
        #expect(result.isError)
        #expect(scheduler.scheduledDates.isEmpty)
    }

    @Test("Denied system authorization still reports a saved follow-up")
    @MainActor func denied() async throws {
        let scheduler = FakeFollowUpScheduler()
        scheduler.deliveryStatus = .permissionDenied
        let tool = FollowUpTool(scheduler: scheduler)
        let result = try await tool.execute(call(), agent: agent())
        #expect(!result.isError)
        #expect(result.content.contains("permission_denied"))
        #expect(result.content.contains("saved"))
        #expect(scheduler.scheduledDates.count == 1)
    }

    @Test("Non-prompting contexts cannot request OS authorization")
    @MainActor func cannotPrompt() async throws {
        let scheduler = FakeFollowUpScheduler()
        let spaceID = UUID()
        let tool = FollowUpTool(scheduler: scheduler, spaceID: spaceID, canPromptUser: false)
        let result = try await tool.execute(call(), agent: agent())
        #expect(!result.isError)
        #expect(scheduler.prompted == false)
        #expect(scheduler.spaceID == spaceID)
    }

    @Test("Scheduling failures are returned to the agent")
    @MainActor func schedulingFailure() async throws {
        let scheduler = FakeFollowUpScheduler()
        scheduler.error = NSError(domain: "Test", code: 1)
        let tool = FollowUpTool(scheduler: scheduler)
        let result = try await tool.execute(call(), agent: agent())
        #expect(result.isError)
        #expect(!result.content.contains("notification_scheduled"))
    }

    @Test("Chat grants and restrictions leave background permissions unchanged")
    func permissions() {
        var policy = AgentPermissionPolicy(
            builtInGrants: [:],
            discoveredGrants: [:],
            chatGrants: [],
            canPromptUser: true
        )
        #expect(policy.permissionLevel(for: "follow_up") == .ask)
        #expect(policy.permissionLevel(for: "background_notify") == .always)
        policy.grantForChat([FollowUpTool.capability])
        #expect(policy.permissionLevel(for: "follow_up") == .always)
        let denied = AgentPermissionPolicy(
            builtInGrants: ["follow_up": .never],
            discoveredGrants: [:],
            chatGrants: [],
            canPromptUser: true
        )
        #expect(denied.permissionLevel(for: "follow_up") == .never)
        #expect(denied.permissionLevel(for: "background_notify") == .always)
    }
}
