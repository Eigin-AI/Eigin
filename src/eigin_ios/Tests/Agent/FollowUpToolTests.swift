@testable import Eigin
import Foundation
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
