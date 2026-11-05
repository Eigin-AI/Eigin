@testable import Eigin
import Foundation
import SwiftData
import Testing

@Suite("Follow-up approval and delivery", .serialized)
struct FollowUpApprovalTests {
    @MainActor
    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition() {
            guard Date() < deadline else { throw NSError(domain: "TestTimeout", code: 1) }
            try await Task.sleep(for: .milliseconds(1))
        }
    }

    @Test(
        "Approval gates authorization and success waits for notification acceptance",
        arguments: [true, false]
    )
    @MainActor func approval(approve: Bool) async throws {
        let container = try ModelContainer(
            for: Schema(SchemaV12.models, version: SchemaV12.versionIdentifier),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let provider = Provider(name: "Test", baseURL: "https://fake.local")
        let agent = Agent(name: "Test", providerID: provider.id, model: "test")
        container.mainContext.insert(provider)
        container.mainContext.insert(agent)
        try container.mainContext.save()
        let authorization = FakeNotificationAuthorization(status: .notDetermined)
        let center = FakeLocalNotificationCenter()
        center.suspendAcceptance = true
        let scheduler = DefaultFollowUpScheduler(
            container: container,
            contentPreparer: FakeCommunicationNotificationPreparer(),
            notificationCenter: center
        )
        let tool = FollowUpTool(scheduler: scheduler, authorize: {
            await NotificationPermission.requestIfNeeded(
                canPromptUser: $0,
                authorization: authorization
            )
        })
        let registry = ToolRegistry(tools: [tool])
        let deadline = ISO8601DateFormatter().string(from: Date().addingTimeInterval(3600))
        let args = [
            "notification_title": "Check in",
            "message": "Prepared message",
            "summary": "Briefing",
            "deliver_at": deadline,
        ]
        let call = try ToolCall(
            id: "follow",
            type: "function",
            function: .init(
                name: "follow_up",
                arguments: String(decoding: JSONEncoder().encode(args), as: UTF8.self)
            )
        )
        let chatService = FakeChatService()
        chatService.enqueueEventStream([.toolCall(call), .finished(.toolCalls)])
        chatService.enqueueEventStream([.contentDelta("Done"), .finished(.stop)])
        let policy = AgentPermissionPolicy(
            builtInGrants: [:],
            discoveredGrants: [:],
            chatGrants: [],
            canPromptUser: true
        )
        let loop = AgenticChatLoop(isBootstrap: false, permissionPolicy: policy)
        var finished = false
        let task = Task { @MainActor in
            let result = try await loop.run(
                messages: [ChatMessage(role: "user", content: "Notify me in an hour")],
                tools: registry.definitions,
                agent: agent,
                provider: provider,
                chatService: chatService,
                toolExecutor: registry
            )
            finished = true
            return result
        }
        defer {
            _ = loop.stop()
            center.accept()
            task.cancel()
        }
        try await waitUntil { loop.pendingPermission != nil }
        #expect(await authorization.requestCount == 0)
        #expect(center.requests.isEmpty)
        #expect(try container.mainContext
            .fetchCount(FetchDescriptor<AgentInitiativeRequest>()) == 0)
        loop.resolvePermission(approve ? .allowOnce : .deny)
        if approve {
            try await waitUntil { center.isWaitingForAcceptance }
            #expect(await authorization.requestCount == 1)
            #expect(!finished)
            #expect(center.requests.isEmpty)
            center.accept()
        }
        let messages = try await task.value
        let result = try #require(messages.first { $0.role == "tool" })
        let records = try container.mainContext.fetch(FetchDescriptor<AgentInitiativeRequest>())
        if approve {
            #expect(result.content?.contains("notification_scheduled") == true)
            let record = try #require(records.first)
            let request = try #require(center.requests.first)
            #expect(record.message == "Prepared message")
            #expect(record.summary == "Briefing")
            #expect(request.content.userInfo["initiativeRequestID"] as? String == record.id
                .uuidString)
        } else {
            #expect(result.content?.contains("notification_scheduled") != true)
            #expect(await authorization.requestCount == 0)
            #expect(center.requests.isEmpty)
            #expect(records.isEmpty)
        }
    }
}
