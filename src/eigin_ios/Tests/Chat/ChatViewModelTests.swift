@testable import Eigin
import Factory
import Foundation
import SwiftData
import Testing
import UIKit

@Suite("ChatViewModel", .serialized)
struct ChatViewModelTests {
    // MARK: - Helpers

    @MainActor
    private func makeContext() throws -> (Chat, Agent, Provider, ModelContainer) {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Schema(SchemaV15.models, version: SchemaV15.versionIdentifier),
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

    @Test("Icebreakers stay unavailable for initiative chats across startup and reload")
    @MainActor
    func initiativeIcebreakerEligibility() async throws {
        let (chat, _, _, container) = try makeContext()
        let occurrence = InitiativeOccurrence(
            id: "icebreaker-occurrence", registrationID: "icebreaker-test",
            deliveredAt: .now, chatID: chat.id, intentIDs: []
        )
        container.mainContext.insert(occurrence)
        try container.mainContext.save()
        let vm = makeViewModel(chat: chat, container: container)
        #expect(!vm.allowsIcebreakers)
        await vm.preloadAllMessages().value
        #expect(vm.window.isPreloaded)
        #expect(vm.chatItems.isEmpty)
        #expect(!vm.allowsIcebreakers)

        occurrence.startedAt = .now
        try container.mainContext.save()
        #expect(!vm.allowsIcebreakers)
        occurrence.completedAt = .now
        try container.mainContext.save()
        #expect(!vm.allowsIcebreakers)

        let reopened = makeViewModel(chat: chat, container: container)
        await reopened.preloadAllMessages().value
        #expect(reopened.window.isPreloaded)
        #expect(!reopened.allowsIcebreakers)
    }

    @Test("Ordinary empty chats allow icebreakers after preload, until preparation starts")
    @MainActor
    func emptyChatIcebreakerEligibility() async throws {
        let (chat, agent, provider, container) = try makeContext()
        let service = FakeChatService()
        service.enqueueEventStream([.contentDelta("Hello"), .finished(.stop)])
        let vm = makeViewModel(chat: chat, agent: agent, container: container, chatService: service)
        #expect(!vm.allowsIcebreakers)
        await vm.preloadAllMessages().value
        #expect(vm.window.isPreloaded)
        #expect(vm.allowsIcebreakers)

        vm.continueTurn(agent: agent, provider: provider, space: nil, spaces: [], mcpServers: [])
        #expect(vm.isTurnInProgress)
        #expect(!vm.isStreaming)
        #expect(!vm.allowsIcebreakers)
        vm.handleStop()
        await vm.streamTask?.value
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

        await vm.generateTitle(agent: agent, provider: provider)?.value

        #expect(chat.title == "Trip Planning")
        #expect(chat.titleOrigin == .generated)
    }

    @Test("Deleted chats skip title eligibility and delayed persistence", arguments: [false, true])
    @MainActor
    func deletedChatSkipsPendingWork(saveDeletion: Bool) async throws {
        let (chat, agent, provider, container) = try makeContext()
        let vm = makeViewModel(chat: chat, container: container)
        vm.chat = chat
        let service = SuspendedTitleService()
        Container.shared.chatService.register { service }
        let context = container.mainContext
        try context.save()
        context.delete(chat)
        if saveDeletion { try context.save() }

        #expect(vm.generateTitle(agent: agent, provider: provider) == nil)
        vm.persistMessage(ChatMessage(role: "user", content: "Late user message"))
        vm.persistMessages([ChatMessage(role: "assistant", content: "Late reply")])
        vm.seedTitle(from: "Late seed")
        vm.handleStop()
        try context.save()

        #expect(try context.fetch(FetchDescriptor<Chat>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Message>()).isEmpty)
        #expect(await service.requestCount == 0)
    }

    @Test(
        "Deleting during title generation skips writes and retries",
        arguments: [false, true],
        ["Generated title", ""]
    )
    @MainActor
    func deletedDuringTitleGeneration(saveDeletion: Bool, response: String) async throws {
        let (chat, agent, provider, container) = try makeContext()
        let vm = makeViewModel(chat: chat, container: container)
        vm.chat = chat
        let service = SuspendedTitleService()
        Container.shared.chatService.register { service }
        let context = container.mainContext
        try context.save()

        let task = try #require(vm.generateTitle(agent: agent, provider: provider))
        await service.waitForRequest()
        context.delete(chat)
        if saveDeletion { try context.save() }
        await service.finish(response)
        await task.value
        try context.save()

        #expect(try context.fetch(FetchDescriptor<Chat>()).isEmpty)
        #expect(await service.requestCount == 1)
    }

    @Test(
        "Title generation preserves edits made during the request",
        arguments: ["Generated title", ""]
    )
    @MainActor
    func titleEditedDuringGeneration(response: String) async throws {
        let (chat, agent, provider, container) = try makeContext()
        let vm = makeViewModel(chat: chat, container: container)
        vm.chat = chat
        let service = SuspendedTitleService()
        Container.shared.chatService.register { service }

        let task = try #require(vm.generateTitle(agent: agent, provider: provider))
        await service.waitForRequest()
        chat.title = "My title"
        chat.titleOrigin = .edited
        await service.finish(response)
        await task.value

        #expect(chat.title == "My title")
        #expect(chat.titleOrigin == .edited)
        #expect(await service.requestCount == 1)
    }

    @Test("An empty generated title retries once for an existing chat")
    @MainActor
    func emptyTitleRetries() async throws {
        let (chat, agent, provider, container) = try makeContext()
        let vm = makeViewModel(chat: chat, container: container)
        vm.chat = chat
        let service = SuspendedTitleService()
        Container.shared.chatService.register { service }

        let task = try #require(vm.generateTitle(agent: agent, provider: provider))
        await service.waitForRequest()
        await service.finish("")
        await service.waitForRequest(2)
        await service.finish("Retry title")
        await task.value

        #expect(chat.title == "Retry title")
        #expect(chat.titleOrigin == .generated)
        #expect(await service.requestCount == 2)
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
        chatService: any ChatService
    ) -> ChatViewModel {
        Container.shared.reset()
        Container.shared.modelContainer.register { container }
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

    @Test("A reply completing after deletion cannot recreate the chat", arguments: [false, true])
    @MainActor
    func replyCompletesAfterDeletion(saveDeletion: Bool) async throws {
        let (chat, agent, provider, container) = try makeContext()
        let context = container.mainContext
        try context.save()
        var deleted = false
        let service = ObservedChatService { _, _, _ in
            context.delete(chat)
            if saveDeletion {
                do { try context.save() } catch { Issue.record(error) }
            }
            deleted = true
        }
        service.scripted.enqueueEventStream([.contentDelta("Late reply"), .finished(.stop)])
        let vm = makeViewModel(chat: chat, agent: agent, container: container, chatService: service)
        vm.window.messages = (0 ..< 4).map { _ in ChatMessage(
            role: "assistant",
            content: "Earlier reply"
        ) }

        vm.send(agent: agent, provider: provider, space: nil, spaces: [], mcpServers: [])
        await vm.streamTask?.value
        try context.save()

        #expect(deleted)
        #expect(vm.chatError == nil)
        #expect(!vm.isTurnInProgress)
        #expect(try context.fetch(FetchDescriptor<Chat>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Message>()).isEmpty)
        #expect(service.scripted.capturedMessages.isEmpty)
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

    @Test(
        "Sending during options persists one result through replacement and retry",
        arguments: [false, true]
    )
    @MainActor
    func sendingDuringOptionsKeepsResultsPaired(retry: Bool) async throws {
        let (chat, agent, provider, container) = try makeContext()
        let service = FakeChatService()
        func options(_ id: String) -> [ChatStreamEvent] {
            [.toolCall(ToolCall(
                id: id, type: "function",
                function: .init(
                    name: "present_options",
                    arguments: #"{"options":[{"label":"Continue","description":"Continue"}]}"#
                )
            )), .finished(.toolCalls)]
        }
        service.enqueueEventStreams([
            options("original"), options("replacement"),
            [.contentDelta("Done"), .finished(.stop)],
        ])
        let vm = makeViewModel(chat: chat, agent: agent, container: container, chatService: service)
        vm.window.isPreloaded = true
        defer { vm.handleStop() }
        vm.send(agent: agent, provider: provider, space: nil, spaces: [], mcpServers: [])
        let firstTask = vm.streamTask
        let deadline = ContinuousClock.now + .seconds(5)
        while vm.chatLoop.pendingOptions?.id != "original", ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(vm.chatLoop.pendingOptions?.id == "original")
        vm.messageText = "Something else"
        if retry {
            service.throwOnEventStream(OpenAICompatibleClientError.httpError(400, body: nil))
        }
        vm.send(agent: agent, provider: provider, space: nil, spaces: [], mcpServers: [])
        await firstTask?.value
        if retry {
            await vm.streamTask?.value
            #expect(vm.chatError != nil)
            vm.retryLastTurn(
                agent: agent,
                provider: provider,
                space: nil,
                spaces: [],
                mcpServers: []
            )
        }
        #expect(vm.isTurnInProgress)
        let replacementDeadline = ContinuousClock.now + .seconds(5)
        while vm.chatLoop.pendingOptions?.id != "replacement",
              ContinuousClock.now < replacementDeadline
        {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(vm.chatLoop.pendingOptions?.id == "replacement")
        #expect(vm.chatLoop.isAwaitingUserInteraction)
        #expect(vm.window.allPersisted.count { $0.toolCallID == "original" } == 1)
        #expect(service.capturedEventMessages.count { $0.toolCallID == "original" } == 1)
        vm.chatLoop.resolveOptions(.selected(label: "Continue"))
        await vm.streamTask?.value
        #expect(vm.chatError == nil)
        #expect(!vm.isTurnInProgress)
        #expect(vm.window.allPersisted.count { $0.toolCallID == "original" } == 1)
        #expect(vm.window.allPersisted.count { $0.toolCallID == "replacement" } == 1)
        #expect(service.capturedEventMessages.count { $0.toolCallID == "replacement" } == 1)
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
        #expect(!vm.isStreaming)
        #expect(!vm.isTurnInProgress)
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

    @Test("retry preserves image files and replays the original attachment references")
    @MainActor
    func retryPreservesAttachments() async throws {
        let (chat, agent, provider, container) = try makeContext()
        let service = FakeChatService()
        service.throwOnEventStream(URLError(.cannotConnectToHost))
        let vm = makeViewModel(chat: chat, agent: agent, container: container, chatService: service)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DefaultChatAttachmentStore(root: root)
        Container.shared.chatAttachmentStore.register { store }
        let image = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        }
        let attachment = try store.save(
            imageData: #require(image.jpegData(compressionQuality: 0.9)),
            id: UUID()
        )
        vm.stagedAttachments = [attachment]
        vm.send(agent: agent, provider: provider, space: nil, spaces: [], mcpServers: [])
        await vm.streamTask?.value
        #expect(vm.chatError != nil)
        let original = try #require(vm.window.messages.last)
        service.enqueueEventStream([.contentDelta("I can see the image"), .finished(.stop)])
        vm.retryLastTurn(agent: agent, provider: provider, space: nil, spaces: [], mcpServers: [])
        await vm.streamTask?.value
        #expect(store.load(id: attachment.id) != nil)
        #expect(store.loadThumbnail(id: attachment.id) != nil)
        let replayed = try #require(service.capturedEventMessages
            .last(where: { $0.role == "user" }))
        #expect(replayed.localID == original.localID)
        #expect(vm.window.messages.first(where: { $0.role == "user" })?.attachments?.first?
            .id == attachment.id)
        let rows = try container.mainContext.fetch(FetchDescriptor<Message>())
        #expect(rows.first(where: { $0.role == "user" })?.attachments?.first?.id == attachment.id)
    }

    @Test(
        "continuation after confirmation guidance and a failed response cannot open a connection sheet"
    )
    @MainActor
    func continuationDoesNotCountAsConnectionConsent() async throws {
        let (chat, agent, provider, container) = try makeContext()
        let service = FakeChatService()
        let call = ToolCall(
            id: "connect-health",
            type: "function",
            function: .init(
                name: "activate_skill",
                arguments: #"{"skill_id":"health"}"#
            )
        )
        service.enqueueEventStream([.toolCall(call), .finished(.toolCalls)])
        service.enqueueEventFailure(URLError(.cannotConnectToHost))
        chat.title = "Connection confirmation"
        chat.titleOrigin = .edited
        let vm = makeViewModel(chat: chat, agent: agent, container: container, chatService: service)
        Container.shared.healthService.register { FakeHealthService() }
        DeclinedCapabilities().clear(.health)
        vm.send(agent: agent, provider: provider, space: nil, spaces: [], mcpServers: [])
        await vm.streamTask?.value
        #expect(vm.chatError != nil)
        #expect(service.capturedEventMessages
            .contains {
                $0.role == "tool" && ($0.content?.contains("confirmation_required") ?? false)
            })
        let originalID = try #require(vm.window.messages.first(where: { $0.role == "user" })?
            .localID)
        service.enqueueEventStream([.toolCall(call), .finished(.toolCalls)])
        service.enqueueEventStream([
            .contentDelta("May I open the connection screen?"),
            .finished(.stop),
        ])
        vm.continueTurn(agent: agent, provider: provider, space: nil, spaces: [], mcpServers: [])
        // A broken gate waits on a sheet here; stop it so the regression fails without hanging.
        for _ in 0 ..< 1000 {
            if !vm.isTurnInProgress || vm.chatLoop.pendingConnection != nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let openedOnRetry = vm.chatLoop.pendingConnection != nil
        if vm.isTurnInProgress { vm.handleStop() }
        await vm.streamTask?.value
        #expect(!openedOnRetry)
        #expect(vm.window.messages.first(where: { $0.role == "user" })?.localID == originalID)
        #expect(service.capturedEventMessages
            .contains {
                $0.role == "tool" && ($0.content?.contains("confirmation_required") ?? false)
            })

        service.enqueueEventStream([.toolCall(call), .finished(.toolCalls)])
        service.enqueueEventStream([.contentDelta("Okay"), .finished(.stop)])
        vm.messageText = "Yes, open it"
        vm.send(agent: agent, provider: provider, space: nil, spaces: [], mcpServers: [])
        for _ in 0 ..< 1000 {
            if !vm.isTurnInProgress || vm.chatLoop.pendingConnection != nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(vm.chatLoop.pendingConnection?.capabilities == [.health])
        vm.chatLoop.resolveConnection(.cancelled)
        if vm.isTurnInProgress, vm.chatLoop.pendingConnection != nil { vm.handleStop() }
        await vm.streamTask?.value
    }

    // MARK: - continueTurn

    @Test(
        "recovery continues saved work without resending or duplicate taps",
        arguments: [false, true]
    )
    @MainActor
    func recoveryContinuesSavedWork(credits: Bool) async throws {
        let (chat, agent, provider, container) = try makeContext()
        let service = FakeChatService()
        let call = ToolCall(
            id: "completed",
            type: "function",
            function: .init(name: "read_core", arguments: "{\"core\":\"identity\"}")
        )
        service.enqueueEventStream([.toolCall(call), .finished(.toolCalls)])
        if credits {
            service.enqueueEventFailure(CreditsError.noCreditsRemaining)
        } else {
            service.enqueueEventStreams([[.finished(.stop)], [.finished(.stop)]])
        }
        let vm = makeViewModel(chat: chat, agent: agent, container: container, chatService: service)
        vm.continueTurn(agent: agent, provider: provider, space: nil, spaces: [], mcpServers: [])
        await vm.streamTask?.value
        #expect(vm.chatError?.recovery == (credits ? .purchaseEiginRelayCredits : .continueTurn))
        #expect(vm.window.messages.count(where: { $0.toolCallID == "completed" }) == 1)
        #expect(vm.chatLoop.committedMessages.isEmpty)
        let userCount = vm.window.messages.count(where: { $0.role == "user" })
        service.enqueueEventStream([.contentDelta("Done."), .finished(.stop)])
        vm.continueTurn(
            agent: agent,
            provider: provider,
            space: nil,
            spaces: [],
            mcpServers: [],
            continuationInstruction: Prompt.Hints.Continuation.interrupted
        )
        vm.continueTurn(
            agent: agent,
            provider: provider,
            space: nil,
            spaces: [],
            mcpServers: [],
            continuationInstruction: Prompt.Hints.Continuation.interrupted
        )
        await vm.streamTask?.value
        #expect(vm.chatError == nil)
        #expect(vm.window.messages.last?.content == "Done.")
        #expect(vm.window.messages.count(where: { $0.role == "user" }) == userCount)
        #expect(vm.window.messages.count(where: { $0.toolCallID == "completed" }) == 1)
        #expect(service.capturedEventMessages.contains { $0.toolCallID == "completed" })
        #expect(!vm.window.messages
            .contains { ($0.content ?? "").contains(Prompt.Hints.Continuation.interrupted) })
    }

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

    @Test(
        "initiatives start and explicitly resume without a visible user message",
        arguments: [false, true]
    )
    @MainActor
    func initiativeStartsAndResumesWithoutUserMessage(interrupted: Bool) async throws {
        let (chat, agent, provider, container) = try makeContext()
        let context = container.mainContext
        let schedule = IntentSchedule(content: "News", frequency: .daily, hour: 7, minute: 0)
        let intent = Intent(agentID: agent.id, content: "News", schedules: [schedule])
        let agreement = IntentInitiative(
            intentID: intent.id,
            scheduleID: schedule.id,
            instructions: "Get news",
            notificationBody: "Time for news"
        )
        let delivery = InitiativeDelivery(
            agentID: agent.id,
            spaceID: nil,
            hour: 7,
            minute: 0,
            weekday: nil,
            members: [
                .init(
                    initiativeID: agreement.id,
                    intentID: intent.id,
                    schedule: schedule,
                    instructions: agreement.instructions,
                    body: agreement.notificationBody,
                    revision: agreement.updatedAt
                ),
            ]
        )
        context.insert(intent)
        context.insert(agreement)
        try context.insert(InitiativeRegistration(id: "resume-test", payload: delivery.encoded()))
        context.insert(InitiativeOccurrence(
            id: "resume-occurrence",
            registrationID: "resume-test",
            deliveredAt: .now,
            chatID: chat.id,
            intentIDs: [intent.id]
        ))
        let toolCall = ToolCall(
            id: "already-read",
            type: "function",
            function: .init(name: "web_fetch", arguments: "{}")
        )
        let history: [ChatMessage] = interrupted ? [
            ChatMessage(role: "assistant", content: nil, toolCalls: [toolCall]),
            ChatMessage(
                role: "tool",
                content: "Fetched source already: research release",
                toolCallID: toolCall.id
            ),
            ChatMessage(role: "assistant", content: "Here is the first finding…"),
        ] : []
        let persisted = history.map { message in
            let row = Message.from(message)
            row.chat = chat
            context.insert(row)
            return row
        }
        try context.save()
        if interrupted {
            #expect(try InitiativeConversationService.beginExecution(
                chatID: chat.id, messages: history, context: context
            ))
            InitiativeConversationService.recordOutput(
                persisted[2],
                chatID: chat.id,
                context: context
            )
            try InitiativeConversationService.finishExecution(
                chatID: chat.id,
                completed: false,
                context: context
            )
        }
        let service = FakeChatService()
        service.enqueueEventStream([
            .contentDelta("Continuing from the source already fetched."),
            .finished(.stop),
        ])
        let vm = makeViewModel(chat: chat, agent: agent, container: container, chatService: service)
        await vm.preloadAllMessages().value
        #expect(vm.window.isPreloaded)
        #expect(!vm.allowsIcebreakers)
        #expect(vm.streamTask == nil)
        if interrupted {
            vm.showInitiativeError(InitiativeError.interrupted)
            #expect(vm.canResumeInitiative)
            vm.resumeInitiative(
                agent: agent,
                provider: provider,
                space: nil,
                spaces: [],
                mcpServers: []
            )
        } else {
            #expect(InitiativeConversationService.hasPendingStart(
                chatID: chat.id,
                context: context
            ))
            #expect(try InitiativeConversationService.claimStart(chatID: chat.id, context: context))
            #expect(!vm.allowsIcebreakers)
            vm.continueTurn(
                agent: agent,
                provider: provider,
                space: nil,
                spaces: [],
                mcpServers: []
            )
        }
        await vm.streamTask?.value
        #expect(vm.chatError == nil)
        #expect(!vm.canResumeInitiative)
        #expect(vm.window.messages.last?.content == "Continuing from the source already fetched.")
        if interrupted {
            #expect(service.capturedEventMessages.contains { $0.toolCallID == "already-read" })
        }
        #expect(service.capturedEventMessages.contains { $0.content?.contains("Get news") == true })
        let remaining = try context.fetch(FetchDescriptor<Message>())
        #expect(Set(persisted.map(\.id)).isSubset(of: Set(remaining.map(\.id))))
        #expect(!remaining.contains(where: { $0.role == "user" }))
        #expect(!vm.window.messages.contains(where: { $0.role == "user" }))
        #expect(try context.fetch(FetchDescriptor<InitiativeOccurrence>()).first?
            .completedAt != nil)
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
