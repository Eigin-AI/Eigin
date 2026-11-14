@testable import Eigin
import EiginSDK
import Foundation
import SwiftData
import Testing

@Suite("ContextPagingSession", .serialized)
@MainActor
struct ContextPagingSessionTests {
    private typealias Context = EiginSDK.Experimental.Context
    private var policy: Context.PagingPolicy {
        .init(triggerTokens: 500, targetTokens: 250, maximumTokens: 700)
    }

    private func history() -> [ChatMessage] {
        let call = ToolCall(
            id: "read",
            type: "function",
            function: .init(name: "read", arguments: "{}")
        )
        return [
            ChatMessage(role: "system", content: "Instructions"),
            ChatMessage(role: "user", content: "Read this"),
            ChatMessage(role: "assistant", toolCalls: [call]),
            ChatMessage(
                role: "tool",
                content: String(repeating: "payload ", count: 500),
                toolCallID: "read"
            ),
            ChatMessage(role: "assistant", content: "Read"),
            ChatMessage(role: "user", content: "Next"), ChatMessage(
                role: "assistant",
                content: "Done"
            ),
            ChatMessage(role: "user", content: "Again"), ChatMessage(
                role: "assistant",
                content: "Done"
            ),
            ChatMessage(role: "user", content: "Continue"),
        ]
    }

    private func store() throws -> (ModelContainer, Agent, Chat) {
        let container = try ModelContainer(
            for: Schema(SchemaV16.models, version: SchemaV16.versionIdentifier),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let agent = Agent(name: "Test", providerID: UUID(), model: "test-model")
        let chat = Chat(agentID: agent.id)
        container.mainContext.insert(agent)
        container.mainContext.insert(chat)
        try container.mainContext.save()
        return (container, agent, chat)
    }

    @Test func masksResultsWithoutChangingTranscriptAndReopensWithSameSelection() throws {
        let (container, agent, chat) = try store()
        let input = history()
        for (index, value) in input.dropFirst().enumerated() {
            let message = Message.from(value)
            message.timestamp = Date(timeIntervalSince1970: Double(index))
            message.chat = chat
            container.mainContext.insert(message)
        }
        try container.mainContext.save()
        let session = try ContextPagingSession(agent: agent, chatID: chat.id)
        let otherSurface = try ContextPagingSession(agent: agent, chatID: chat.id)
        let result = try session.prepare(
            input,
            tools: nil,
            model: "test-model",
            origin: nil,
            policy: policy
        )
        #expect(result.first { $0.role == "tool" }?.content == "[omitted]")
        #expect(result.first { $0.role == "tool" }?.toolCallID == "read")
        #expect(result.contains { $0.content?.contains(ContextPagingSession.notice) == true })
        #expect(chat.messages.first { $0.role == "tool" }?.content == input[3].content)
        let largerBudget = Context.PagingPolicy(
            triggerTokens: 10000,
            targetTokens: 5000,
            maximumTokens: 20000
        )
        let shared = try otherSurface.prepare(
            input,
            tools: nil,
            model: "test-model",
            origin: nil,
            policy: largerBudget
        )
        #expect(shared.map(\.content) == result.map(\.content))
        let reopened = try ContextPagingSession(agent: agent, chatID: chat.id)
        let replay = try reopened.prepare(
            input,
            tools: nil,
            model: "test-model",
            origin: nil,
            policy: policy
        )
        #expect(replay.map(\.content) == result.map(\.content))
        #expect(try container.mainContext.fetch(FetchDescriptor<ContextPage>()).count == 1)
        let appended = input + [
            ChatMessage(role: "assistant", content: "Answer"),
            ChatMessage(role: "user", content: "More"),
        ]
        for value in appended.suffix(2) {
            let message = Message.from(value)
            message.chat = chat
            container.mainContext.insert(message)
        }
        try container.mainContext.save()
        let next = try reopened.prepare(
            appended,
            tools: nil,
            model: "test-model",
            origin: nil,
            policy: policy
        )
        #expect(next.first { $0.role == "tool" }?.content == "[omitted]")
        #expect(next
            .count(where: { $0.content?.contains(ContextPagingSession.notice) == true }) == 2)
        #expect(next.last?.content?.contains(ContextPagingSession.notice) == true)
        #expect(!chat.messages.contains { $0.content.contains(ContextPagingSession.notice) })
        #expect(Array(next.prefix(result.count)).map(\.content) == result.map(\.content))
        let afterAppend = try ContextPagingSession(agent: agent, chatID: chat.id)
        let reopenedAppend = try afterAppend.prepare(
            appended,
            tools: nil,
            model: "test-model",
            origin: nil,
            policy: policy
        )
        #expect(reopenedAppend.map(\.content) == next.map(\.content))
        let repeated = try afterAppend.prepare(
            appended,
            tools: nil,
            model: "test-model",
            origin: nil,
            policy: policy
        )
        #expect(repeated.map(\.content) == next.map(\.content))
    }

    @Test func olderSingleNoticeStateKeepsItsHintAndAddsCurrentTurnHint() throws {
        let (container, agent, chat) = try store()
        let input = history()
        for value in input.dropFirst() {
            let message = Message.from(value)
            message.chat = chat
            container.mainContext.insert(message)
        }
        let historicalID = Message.from(input[1]).id.uuidString
        let data = try JSONSerialization.data(withJSONObject: [
            "version": 1, "excludedIDs": [], "maskedIDs": [],
            "hasPaged": true, "hintMessageID": historicalID,
        ])
        container.mainContext.insert(ContextPage(
            chatID: chat.id,
            agentID: agent.id,
            stateData: data
        ))
        try container.mainContext.save()
        let session = try ContextPagingSession(agent: agent, chatID: chat.id)
        let output = try session.prepare(
            input,
            tools: nil,
            model: "test-model",
            origin: nil,
            policy: policy
        )
        #expect(output.first { $0.role == "user" }?.content?
            .contains(ContextPagingSession.notice) == true)
        #expect(output.last?.content?.contains(ContextPagingSession.notice) == true)
        #expect(output
            .count(where: { $0.content?.contains(ContextPagingSession.notice) == true }) == 2)
    }

    @Test func belowThresholdDoesNotAddNoticeOrMutateContent() throws {
        let input = [
            ChatMessage(role: "system", content: "Instructions"),
            ChatMessage(role: "user", content: "Hello"),
        ]
        let session = ContextPagingSession()
        let result = try session.prepare(
            input,
            tools: nil,
            model: "test-model",
            origin: nil,
            policy: policy
        )
        #expect(result.map(\.content) == input.map(\.content))
        #expect(!session.state.hasPaged)
    }

    @Test func textOnlyHistoryEvictsOldTurnsAndCannotResurrectThem() throws {
        var input = [ChatMessage(role: "system", content: "Instructions")]
        for _ in 0 ..< 5 {
            input += [
                ChatMessage(role: "user", content: String(repeating: "x", count: 800)),
                ChatMessage(role: "assistant", content: "OK"),
            ]
        }
        input.append(ChatMessage(role: "user", content: "Continue"))
        let session = ContextPagingSession()
        let output = try session.prepare(
            input,
            tools: nil,
            model: "test-model",
            origin: nil,
            policy: policy
        )
        #expect(output.count < input.count)
        #expect(!output.contains { $0.localID == input[1].localID })
        let large = Context.PagingPolicy(
            triggerTokens: 10000,
            targetTokens: 5000,
            maximumTokens: 20000
        )
        let replay = try session.prepare(
            input,
            tools: nil,
            model: "test-model",
            origin: nil,
            policy: large
        )
        #expect(replay.map(\.localID) == output.map(\.localID))
    }

    @Test func protectedCurrentRequestFailsBeforeDispatch() {
        let input = [ChatMessage(role: "user", content: String(repeating: "x", count: 4000))]
        #expect(throws: ContextPagingSession.Failure.self) {
            try ContextPagingSession().prepare(
                input,
                tools: nil,
                model: "test-model",
                origin: nil,
                policy: policy
            )
        }
    }

    @Test func deletedChatCannotDispatchOrWriteState() throws {
        let (container, agent, chat) = try store()
        let session = try ContextPagingSession(agent: agent, chatID: chat.id)
        container.mainContext.delete(chat)
        #expect(throws: ContextPagingSession.Failure.self) {
            try session.prepare(
                history(),
                tools: nil,
                model: "test-model",
                origin: nil,
                policy: policy
            )
        }
        #expect(throws: ContextPagingSession.Failure.self) { try ContextPagingSession(
            agent: agent,
            chatID: UUID()
        ) }
    }

    @Test func budgetTriggersScaleAndCapAt250K() {
        for size in [16000, 250_000, 500_000, 1_000_000] {
            let p = ContextPagingSession.policy(contextWindow: size, maxOutput: 4096)
            #expect(p.targetTokens == p.triggerTokens / 2)
            #expect(p.triggerTokens <= 250_000)
            #expect(p.triggerTokens < p.maximumTokens)
            #expect(p.maximumTokens < size - min(4096, size / 4))
        }
        #expect(ContextPagingSession.policy(contextWindow: 1_000_000, maxOutput: 4096)
            .triggerTokens == 250_000)
    }

    @Test func migratesV15TranscriptWithoutChangingMessages() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("store.sqlite")
        let messageID = UUID()
        try autoreleasepool {
            let old = try ModelContainer(
                for: Schema(SchemaV15.models, version: SchemaV15.versionIdentifier),
                configurations: ModelConfiguration(url: url)
            )
            let chat = Chat(agentID: UUID())
            old.mainContext.insert(chat)
            let message = Message(role: "user", content: "Keep this transcript")
            message.id = messageID
            message.chat = chat
            old.mainContext.insert(message)
            try old.mainContext.save()
        }
        let migrated = try ModelContainer(
            for: Schema(SchemaV16.models, version: SchemaV16.versionIdentifier),
            migrationPlan: EiginMigrationPlan.self,
            configurations: ModelConfiguration(url: url)
        )
        let messages = try migrated.mainContext.fetch(FetchDescriptor<Message>())
        #expect(messages.count == 1)
        #expect(messages.first?.id == messageID)
        #expect(messages.first?.content == "Keep this transcript")
        #expect(try migrated.mainContext.fetch(FetchDescriptor<ContextPage>()).isEmpty)
    }

    @Test func toolRoundOverflowStopsBeforeAnotherRequestAndKeepsCheckpoint() async throws {
        let (container, agent, chat) = try store()
        let provider = Provider(name: "Test", baseURL: "https://fake.local")
        container.mainContext.insert(provider)
        let user = ChatMessage(role: "user", content: "Read this")
        let persisted = Message.from(user)
        persisted.chat = chat
        container.mainContext.insert(persisted)
        try container.mainContext.save()
        let service = FakeChatService()
        let call = ToolCall(
            id: "large",
            type: "function",
            function: .init(name: "read", arguments: "{}")
        )
        service.enqueueEventStream([.toolCall(call), .finished(.toolCalls)])
        let executor = FakeToolExecutor()
        let payload = String(repeating: "x", count: 500_000)
        executor.setResult(for: call.id, content: payload)
        let loop = AgenticChatLoop(isBootstrap: false, throttler: PassthroughThrottler())
        await #expect(throws: ContextPagingSession.Failure.self) {
            try await loop.run(
                messages: [user],
                tools: nil,
                agent: agent,
                provider: provider,
                chatService: service,
                toolExecutor: executor,
                conversationID: chat.id
            )
        }
        #expect(service.capturedEventMessages.count == 1)
        #expect(loop.buildCheckpoint().contains { $0.role == "tool" && $0.content == payload })
        #expect(service.capturedMessages.isEmpty)
        loop.settle()
    }

    @Test func outputCeilingEqualToWindowDoesNotRejectShortRequests() throws {
        let p = ContextPagingSession.policy(model: "mistral-medium-3-5")
        #expect(p.maximumTokens > 100_000)
        try ContextPagingSession.validate(
            [ChatMessage(role: "user", content: "Hello")],
            tools: nil,
            model: "mistral-medium-3-5",
            origin: nil
        )
    }

    @Test func olderSummaryRowsAreExcludedFromRetainedHistory() throws {
        var first = ChatMessage(role: "system", content: "Old summary")
        first.isCompactionSummary = true
        var second = ChatMessage(role: "system", content: "New summary")
        second.isCompactionSummary = true
        second.compactionRetainedMessageCount = 3
        let recent = ChatMessage(role: "user", content: "Recent")
        let split = MessagePipeline.splitAtLatestSummary([
            first,
            recent,
            ChatMessage(role: "assistant", content: "OK"),
            second,
        ])
        #expect(split.summary == "New summary")
        #expect(split.conversation.map(\.role) == ["user", "assistant"])
        let result = try ContextPagingSession().prepare(
            split.conversation,
            tools: nil,
            model: "test-model",
            origin: nil
        )
        #expect(result.map(\.content) == split.conversation.map(\.content))
    }

    @Test func chatlessLoopRetainsItsPageAcrossUserTurns() async throws {
        let (container, agent, _) = try store()
        let provider = Provider(name: "Test", baseURL: "https://fake.local")
        container.mainContext.insert(provider)
        var input = history()
        input[3].content = String(repeating: "x", count: 400_000)
        let service = FakeChatService()
        service.enqueueEventStream([.contentDelta("Answer"), .finished(.stop)])
        service.enqueueEventStream([.contentDelta("Next answer"), .finished(.stop)])
        let loop = AgenticChatLoop(isBootstrap: false, throttler: PassthroughThrottler())
        let produced = try await loop.run(
            messages: input,
            tools: nil,
            agent: agent,
            provider: provider,
            chatService: service,
            toolExecutor: FakeToolExecutor()
        )
        let first = service.capturedEventMessages
        loop.settle()
        _ = try await loop.run(
            messages: input + produced + [ChatMessage(role: "user", content: "More")],
            tools: nil,
            agent: agent,
            provider: provider,
            chatService: service,
            toolExecutor: FakeToolExecutor()
        )
        #expect(first.first { $0.role == "tool" }?.content == "[omitted]")
        #expect(service.capturedEventMessages.last?.content?
            .contains(ContextPagingSession.notice) == true)
        #expect(service.capturedEventMessages
            .count(where: { $0.content?.contains(ContextPagingSession.notice) == true }) == 2)
        #expect(Array(service.capturedEventMessages.prefix(first.count)).map(\.content) == first
            .map(\.content))
        loop.settle()
    }

    @Test func schemaGrowthAloneRejectsAnOversizedRequest() throws {
        let input = [ChatMessage(role: "user", content: "Hello")]
        let small = ToolDefinition(
            name: "test",
            description: "Test",
            parameters: .init(type: "object")
        )
        let large = ToolDefinition(
            name: "test",
            description: "Test",
            parameters: .init(type: "object", properties: [
                "value": .init(
                    type: "string",
                    description: String(repeating: "schema ", count: 2000)
                ),
            ])
        )
        _ = try ContextPagingSession().prepare(
            input,
            tools: [small],
            model: "test-model",
            origin: nil,
            policy: policy
        )
        #expect(throws: ContextPagingSession.Failure.self) {
            try ContextPagingSession().prepare(
                input,
                tools: [large],
                model: "test-model",
                origin: nil,
                policy: policy
            )
        }
        #expect(TokenEstimator
            .estimateRequest(messages: input, toolDefinitions: [large]) > TokenEstimator
            .estimateRequest(
                messages: input,
                toolDefinitions: [small]
            ))
    }

    @Test func attachmentsContributeToPagingAndDispatchBudgets() throws {
        var input = history()
        input[3].content = "Short result"
        let image = MessageAttachment(
            kind: .image,
            mimeType: "image/jpeg",
            width: 1024,
            height: 1024,
            byteCount: 100_000
        )
        input[1].attachments = [image]
        let result = try ContextPagingSession().prepare(
            input,
            tools: nil,
            model: "gpt-4o-mini",
            origin: nil,
            policy: policy
        )
        #expect(!result.contains { $0.localID == input[1].localID })
        #expect(input[1].attachments == [image])
        var current = ChatMessage(role: "user", content: "Describe these")
        current.attachments = Array(repeating: image, count: 4)
        #expect(throws: ContextPagingSession.Failure.self) {
            try ContextPagingSession.validate(
                [current],
                tools: nil,
                model: "gpt-4o-mini",
                origin: nil
            )
        }
        #expect(throws: ContextPagingSession.Failure.self) {
            try ContextPagingSession().prepare(
                [current],
                tools: nil,
                model: "gpt-4o-mini",
                origin: nil
            )
        }
    }
}
