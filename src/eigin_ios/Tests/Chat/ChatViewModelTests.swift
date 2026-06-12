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
            for: Schema(SchemaV1.models, version: SchemaV1.versionIdentifier),
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
}
