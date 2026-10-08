@testable import Eigin
import Factory
import Foundation
import SwiftData
import Testing

@Suite("ChatViewModel", .serialized)
struct ChatViewModelTests {
    // MARK: - Helpers

    @MainActor
    private func makeContext() throws -> (Chat, Agent, Provider, ModelContainer) {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Schema(SchemaV10.models, version: SchemaV10.versionIdentifier),
            configurations: config
        )
        let ctx = container.mainContext

        let provider = Provider(name: "Test", baseURL: "https://fake.local")
        ctx.insert(provider)

        let agent = Agent(name: "TestAgent", providerID: provider.id, model: "test-model")
        agent.bootstrapComplete = true
        agent.identityCore = "Test"
        agent.userCore = "Test"
        agent.soulCore = ""
        ctx.insert(agent)

        let chat = Chat(agentID: agent.id, spaceID: nil)
        ctx.insert(chat)

        return (chat, agent, provider, container)
    }

    @MainActor
    private func makeViewModel(
        chat: Chat,
        container: ModelContainer
    ) -> ChatViewModel {
        Container.shared.reset()
        Container.shared.chatService.register { FakeChatService() }
        Container.shared.knowledgeService.register { PreviewKnowledgeService() }
        Container.shared.intentService.register { PreviewIntentService() }

        let vm = ChatViewModel(chatID: chat.id)
        vm.setUp(modelContext: container.mainContext)
        return vm
    }

    // MARK: - cleanTitle

    @Test("cleanTitle strips wrapping quotes")
    func cleanTitleStripsQuotes() {
        #expect(ChatTitleGenerator.cleanTitle("\"My Title\"") == "My Title")
        #expect(ChatTitleGenerator.cleanTitle("'My Title'") == "My Title")
    }

    @Test("cleanTitle trims whitespace")
    func cleanTitleTrimsWhitespace() {
        #expect(ChatTitleGenerator.cleanTitle("  Hello  ") == "Hello")
    }

    @Test("cleanTitle returns nil for empty")
    func cleanTitleNilForEmpty() {
        #expect(ChatTitleGenerator.cleanTitle("") == nil)
        #expect(ChatTitleGenerator.cleanTitle("  ") == nil)
        #expect(ChatTitleGenerator.cleanTitle("\"\"") == nil)
    }

    @Test("cleanTitle truncates at 40 chars on word boundary")
    func cleanTitleTruncates() throws {
        let long = "This is a very long title that definitely exceeds the forty character limit"
        let result = try #require(ChatTitleGenerator.cleanTitle(long))
        #expect(result.count <= 40)
        #expect(!result.hasSuffix(" "))
    }

    // MARK: - Pagination

    @Test("snapToBottom shows last page of messages")
    @MainActor
    func snapToBottom() throws {
        let (chat, _, _, container) = try makeContext()
        let vm = makeViewModel(chat: chat, container: container)

        // Simulate preloaded state with 50 messages
        vm.window.isPreloaded = true
        vm.window.allPersisted = (0 ..< 50).map { i in
            let msg = Message(role: "user", content: "Message \(i)")
            msg.chat = chat
            return msg
        }
        vm.window.messages = []
        vm.window.windowStartIndex = 0

        vm.window.snapToBottom()

        #expect(vm.window.windowStartIndex == 20) // 50 - pageBudget(30)
        #expect(vm.window.messages.count == 30)
    }

    @Test("hasOlderMessages is true when window doesn't start at 0")
    @MainActor
    func hasOlderMessages() throws {
        let (chat, _, _, container) = try makeContext()
        let vm = makeViewModel(chat: chat, container: container)

        vm.window.isPreloaded = true
        vm.window.windowStartIndex = 10
        #expect(vm.window.hasOlderMessages == true)

        vm.window.windowStartIndex = 0
        #expect(vm.window.hasOlderMessages == false)
    }

    @Test("hasNewerMessages is true when window doesn't reach the end")
    @MainActor
    func hasNewerMessages() throws {
        let (chat, _, _, container) = try makeContext()
        let vm = makeViewModel(chat: chat, container: container)

        vm.window.isPreloaded = true
        vm.window.allPersisted = (0 ..< 50).map { i in
            let msg = Message(role: "user", content: "Message \(i)")
            msg.chat = chat
            return msg
        }
        vm.window.windowStartIndex = 0
        vm.window.messages = Array(repeating: ChatMessage(role: "user", content: "x"), count: 15)

        #expect(vm.window.hasNewerMessages == true) // 0 + 15 < 50

        vm.window.windowStartIndex = 35
        #expect(vm.window.hasNewerMessages == false) // 35 + 15 = 50
    }

    // MARK: - seedTitle

    @Test("seedTitle sets title from first sentence")
    @MainActor
    func seedTitleSetsFromFirstSentence() throws {
        let (chat, _, _, container) = try makeContext()
        let vm = makeViewModel(chat: chat, container: container)
        vm.chat = chat
        chat.title = ""

        vm.seedTitle(from: "Help me plan a trip. I want to go somewhere warm.")

        #expect(chat.title == "Help me plan a trip")
        #expect(chat.titleOrigin == .seeded)
    }

    @Test("seedTitle does not overwrite existing title")
    @MainActor
    func seedTitleDoesNotOverwrite() throws {
        let (chat, _, _, container) = try makeContext()
        let vm = makeViewModel(chat: chat, container: container)
        vm.chat = chat
        chat.title = "Existing Title"

        vm.seedTitle(from: "Something else entirely.")

        #expect(chat.title == "Existing Title")
    }

    // MARK: - generateTitle

    @Test("generateTitle uses chat service to set title")
    @MainActor
    func generateTitleSetsTitle() async throws {
        let (chat, agent, provider, container) = try makeContext()

        Container.shared.reset()
        let fakeChatService = FakeChatService()
        fakeChatService.enqueueTokens(["Trip", " ", "Planning"])
        Container.shared.chatService.register { fakeChatService }
        Container.shared.knowledgeService.register { PreviewKnowledgeService() }
        Container.shared.intentService.register { PreviewIntentService() }

        let vm = ChatViewModel(chatID: chat.id)
        vm.setUp(modelContext: container.mainContext)
        vm.chat = chat
        chat.title = ""
        chat.titleOrigin = .seeded
        vm.window.messages = [
            ChatMessage(role: "user", content: "Plan a trip"),
            ChatMessage(role: "assistant", content: "Where to?"),
        ]

        vm.generateTitle(agent: agent, provider: provider)

        // Wait for the async title generation task
        try await Task.sleep(for: .milliseconds(100))

        #expect(chat.title == "Trip Planning")
        #expect(chat.titleOrigin == .generated)
    }

    @Test("generateTitle skips if already generated")
    @MainActor
    func generateTitleSkipsIfGenerated() throws {
        let (chat, agent, provider, container) = try makeContext()
        let vm = makeViewModel(chat: chat, container: container)
        vm.chat = chat
        chat.title = "Already Set"
        chat.titleOrigin = .generated

        vm.generateTitle(agent: agent, provider: provider)

        #expect(chat.title == "Already Set")
    }

    // MARK: - Cancellation vs. errors

    @MainActor
    private func makeViewModel(
        chat: Chat,
        agent: Agent,
        container: ModelContainer,
        chatService: FakeChatService
    ) -> ChatViewModel {
        Container.shared.reset()
        Container.shared.chatService.register { chatService }
        Container.shared.knowledgeService.register { PreviewKnowledgeService() }
        Container.shared.intentService.register { PreviewIntentService() }

        let vm = ChatViewModel(chatID: chat.id)
        vm.setUp(modelContext: container.mainContext)
        vm.chat = chat
        vm.gatekeeper = Gatekeeper(
            proactivity: agent.proactivity,
            knowledgeService: PreviewKnowledgeService()
        )
        vm.messageText = "Hello"
        return vm
    }

    @Test("a thrown non-cancellation error surfaces as a chatError")
    @MainActor
    func realErrorSetsChatError() async throws {
        let (chat, agent, provider, container) = try makeContext()
        let service = FakeChatService()
        service.throwOnEventStream(URLError(.cannotConnectToHost))
        let vm = makeViewModel(chat: chat, agent: agent, container: container, chatService: service)

        vm.send(agent: agent, provider: provider, space: nil, spaces: [], mcpServers: [])
        await vm.streamTask?.value

        #expect(vm.chatError != nil)
    }

    @Test("a cancellation error does not surface as a chatError")
    @MainActor
    func cancellationDoesNotSetChatError() async throws {
        let (chat, agent, provider, container) = try makeContext()
        let service = FakeChatService()
        service.throwOnEventStream(CancellationError())
        let vm = makeViewModel(chat: chat, agent: agent, container: container, chatService: service)

        vm.send(agent: agent, provider: provider, space: nil, spaces: [], mcpServers: [])
        await vm.streamTask?.value

        #expect(vm.chatError == nil)
    }

    @Test("setLiveCallError surfaces the error as a chatError")
    @MainActor
    func setLiveCallErrorSetsChatError() throws {
        let (chat, _, _, container) = try makeContext()
        let vm = makeViewModel(chat: chat, container: container)

        vm.setLiveCallError(URLError(.notConnectedToInternet))

        #expect(vm.chatError != nil)
    }

    // MARK: - retryLastTurn

    @Test("retryLastTurn re-runs the trailing user message without appending a duplicate")
    @MainActor
    func retryLastTurnReRunsUserMessage() async throws {
        let (chat, agent, provider, container) = try makeContext()
        let service = FakeChatService()
        service.enqueueEventStream([
            .contentDelta("Hi back"),
            .finished(.stop),
        ])
        let vm = makeViewModel(chat: chat, agent: agent, container: container, chatService: service)

        // Simulate a prior failed turn: a user message sits as the trailing
        // item with no assistant reply after it.
        let userMessage = ChatMessage(role: "user", content: "Hello")
        vm.window.messages = [userMessage]
        vm.window.isPreloaded = true
        vm.window.allPersisted = [Message.from(userMessage)]
        let userCountBefore = vm.window.messages.count(where: { $0.role == "user" })

        vm.retryLastTurn(
            agent: agent, provider: provider, space: nil, spaces: [], mcpServers: []
        )
        await vm.streamTask?.value

        let userCountAfter = vm.window.messages.count(where: { $0.role == "user" })
        #expect(userCountAfter == userCountBefore, "retry must not duplicate the user message")
        #expect(vm.window.messages.last?.role == "assistant")
        #expect(vm.messageText.isEmpty)
    }

    // MARK: - continueTurn

    @Test("continueTurn lets the agent answer a seal without a user message")
    @MainActor
    func continueTurnAnswersCommit() async throws {
        let (chat, agent, provider, container) = try makeContext()
        let service = FakeChatService()
        service.enqueueEventStream([
            .contentDelta("Want me to set up that morning rundown now?"),
            .finished(.stop),
        ])
        let vm = makeViewModel(chat: chat, agent: agent, container: container, chatService: service)
        vm.messageText = ""

        let commit = ToolCall(
            id: "commit", type: "function",
            function: .init(name: "finish_onboarding", arguments: "{}")
        )
        let history = [
            ChatMessage(role: "user", content: "Ford it is"),
            ChatMessage(role: "assistant", content: nil, toolCalls: [commit]),
            ChatMessage(
                role: "tool",
                content: "{\"result\":{\"status\":\"committed\"}}",
                toolCallID: "commit"
            ),
        ]
        vm.window.messages = history
        vm.window.allPersisted = history.map { Message.from($0) }
        vm.window.isPreloaded = true
        #expect(vm.awaitsAgentReply)

        vm.continueTurn(agent: agent, provider: provider, space: nil, spaces: [], mcpServers: [])
        await vm.streamTask?.value

        #expect(vm.window.messages.count(where: { $0.role == "user" }) == 1)
        #expect(vm.window.messages.last?.content == "Want me to set up that morning rundown now?")
        #expect(service.capturedEventMessages.last?.role == "tool")
    }

    @Test("retryLastTurn is a no-op when the last message is from the assistant")
    @MainActor
    func retryLastTurnNoOpWhenAssistantLast() throws {
        let (chat, agent, provider, container) = try makeContext()
        let service = FakeChatService()
        let vm = makeViewModel(chat: chat, agent: agent, container: container, chatService: service)

        vm.window.messages = [
            ChatMessage(role: "user", content: "Hi"),
            ChatMessage(role: "assistant", content: "Hello there"),
        ]
        let countBefore = vm.window.messages.count

        vm.retryLastTurn(
            agent: agent, provider: provider, space: nil, spaces: [], mcpServers: []
        )

        #expect(vm.window.messages.count == countBefore)
        #expect(vm.messageText == "Hello", "retry on assistant-last must not touch messageText")
    }

    @Test("retryLastTurn is a no-op while a turn is in progress")
    @MainActor
    func retryLastTurnNoOpWhileStreaming() async throws {
        let (chat, agent, provider, container) = try makeContext()
        let service = FakeChatService()
        // A long-running stream that we won't await — keeps the turn in progress.
        service.enqueueEventStream([.contentDelta("…"), .finished(.stop)])
        let vm = makeViewModel(chat: chat, agent: agent, container: container, chatService: service)
        vm.messageText = "Hello"
        vm.send(agent: agent, provider: provider, space: nil, spaces: [], mcpServers: [])

        // Turn in progress; retry should bail out without queuing a new turn.
        // The single user message from `send` is still the last item, and
        // no second assistant turn should be produced.
        #expect(vm.isTurnInProgress)
        let userCountDuringStream = vm.window.messages.count(where: { $0.role == "user" })
        vm.retryLastTurn(
            agent: agent, provider: provider, space: nil, spaces: [], mcpServers: []
        )
        #expect(vm.window.messages.count(where: { $0.role == "user" }) == userCountDuringStream)

        // Clean up.
        vm.handleStop()
        await vm.streamTask?.value
    }

    @Test("retryLastTurn cannot be triggered twice in quick succession")
    @MainActor
    func retryLastTurnGuardsAgainstRapidRetrigger() async throws {
        let (chat, agent, provider, container) = try makeContext()
        let service = FakeChatService()
        service.enqueueEventStream([.contentDelta("Hi back"), .finished(.stop)])
        let vm = makeViewModel(chat: chat, agent: agent, container: container, chatService: service)

        let userMessage = ChatMessage(role: "user", content: "Hello")
        vm.window.messages = [userMessage]
        vm.window.isPreloaded = true
        vm.window.allPersisted = [Message.from(userMessage)]

        // First retry kicks off a turn (isTurnInProgress becomes true inside
        // `send`, synchronously, before the run loop yields). A second retry
        // call before the task completes must be a no-op — no second rewind,
        // no duplicate user message.
        vm.retryLastTurn(
            agent: agent, provider: provider, space: nil, spaces: [], mcpServers: []
        )
        vm.retryLastTurn(
            agent: agent, provider: provider, space: nil, spaces: [], mcpServers: []
        )
        await vm.streamTask?.value

        let userCount = vm.window.messages.count(where: { $0.role == "user" })
        #expect(userCount == 1, "rapid retrigger must not duplicate the user message")
    }

    @Test("retryLastTurn clears chatError before re-running")
    @MainActor
    func retryLastTurnClearsChatError() async throws {
        let (chat, agent, provider, container) = try makeContext()
        let service = FakeChatService()
        // First call fails; second succeeds.
        service.throwOnEventStream(URLError(.cannotConnectToHost))
        service.enqueueEventStream([.contentDelta("ok"), .finished(.stop)])
        let vm = makeViewModel(chat: chat, agent: agent, container: container, chatService: service)

        vm.messageText = "Hello"
        vm.send(agent: agent, provider: provider, space: nil, spaces: [], mcpServers: [])
        await vm.streamTask?.value
        #expect(vm.chatError != nil)

        // The trailing message is the user message (send errored before any
        // assistant content); retry should clear the error and run the turn.
        vm.retryLastTurn(
            agent: agent, provider: provider, space: nil, spaces: [], mcpServers: []
        )
        #expect(vm.chatError == nil)
        await vm.streamTask?.value
        #expect(vm.window.messages.last?.role == "assistant")
    }

    @Test("retryLastTurn is a no-op when the trailing user message has empty content")
    @MainActor
    func retryLastTurnNoOpOnEmptyContent() throws {
        let (chat, agent, provider, container) = try makeContext()
        let service = FakeChatService()
        let vm = makeViewModel(chat: chat, agent: agent, container: container, chatService: service)

        vm.window.messages = [ChatMessage(role: "user", content: "   ")]
        let countBefore = vm.window.messages.count

        vm.retryLastTurn(
            agent: agent, provider: provider, space: nil, spaces: [], mcpServers: []
        )

        #expect(vm.window.messages.count == countBefore)
        #expect(vm.messageText == "Hello", "retry on empty content must not touch messageText")
    }

    // MARK: - moveToSpace

    @Test("moveToSpace updates chat spaceID")
    @MainActor
    func moveToSpace() throws {
        let (chat, _, _, container) = try makeContext()
        let vm = makeViewModel(chat: chat, container: container)
        vm.chat = chat

        let spaceID = UUID()
        vm.moveToSpace(spaceID)

        #expect(chat.spaceID == spaceID)
    }

    @Test("moveToSpace with nil clears space")
    @MainActor
    func moveToSpaceNil() throws {
        let (chat, _, _, container) = try makeContext()
        let vm = makeViewModel(chat: chat, container: container)
        vm.chat = chat
        chat.spaceID = UUID()

        vm.moveToSpace(nil)

        #expect(chat.spaceID == nil)
    }

    // MARK: - stageAttachment

    private func makeAttachment() -> MessageAttachment {
        MessageAttachment(
            id: UUID(),
            kind: .image,
            mimeType: "image/jpeg",
            width: 100,
            height: 100,
            byteCount: 512
        )
    }

    @Test("stageAttachment stages up to the per-message cap")
    @MainActor
    func stageAttachmentUpToCap() throws {
        let (chat, _, _, container) = try makeContext()
        let vm = makeViewModel(chat: chat, container: container)

        for _ in 0 ..< ChatViewModel.maxStagedAttachments {
            #expect(vm.stageAttachment(makeAttachment()) == true)
        }

        #expect(vm.stagedAttachments.count == ChatViewModel.maxStagedAttachments)
    }

    @Test("stageAttachment refuses beyond the per-message cap")
    @MainActor
    func stageAttachmentBeyondCapRefused() throws {
        let (chat, _, _, container) = try makeContext()
        let vm = makeViewModel(chat: chat, container: container)

        for _ in 0 ..< ChatViewModel.maxStagedAttachments {
            vm.stageAttachment(makeAttachment())
        }
        let accepted = vm.stageAttachment(makeAttachment())

        #expect(accepted == false)
        #expect(vm.stagedAttachments.count == ChatViewModel.maxStagedAttachments)
    }
}
