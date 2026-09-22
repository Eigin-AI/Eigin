@testable import Eigin
import Factory
import Foundation
import SwiftData
import Testing

@Suite("WatchTurnRunner", .serialized)
struct WatchTurnRunnerTests {
    @MainActor
    private func makeContainer() throws -> (Agent, Provider, ModelContainer) {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Schema(SchemaV4.models, version: SchemaV4.versionIdentifier),
            configurations: config
        )
        let provider = Provider(name: "Test", baseURL: "https://fake.local")
        container.mainContext.insert(provider)

        let agent = Agent(name: "TestAgent", providerID: provider.id, model: "test-model")
        agent.identityCore = "I am a test agent."
        agent.userCore = "The user is a tester."
        agent.soulCore = ""
        container.mainContext.insert(agent)

        return (agent, provider, container)
    }

    @MainActor
    private func registerServices(container: ModelContainer, chatService: FakeChatService) {
        Container.shared.reset()
        Container.shared.modelContainer.register { container }
        Container.shared.chatService.register { chatService }
        Container.shared.knowledgeService.register { PreviewKnowledgeService() }
        Container.shared.intentService.register { PreviewIntentService() }
    }

    @MainActor
    private func watchChat(in container: ModelContainer) throws -> Chat {
        let id = try #require(WatchChat.storedID())
        var descriptor = FetchDescriptor<Chat>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try #require(try container.mainContext.fetch(descriptor).first)
    }

    @Test("a turn persists both sides of the exchange to the watch chat")
    @MainActor func turnPersistsToWatchChat() async throws {
        let (agent, provider, container) = try makeContainer()
        let service = FakeChatService()
        service.enqueueEventStream([.contentDelta("Milk added."), .finished(.stop)])
        registerServices(container: container, chatService: service)
        UserDefaults.standard.removeObject(forKey: StorageKey.watchChat)
        defer { UserDefaults.standard.removeObject(forKey: StorageKey.watchChat) }

        let reply = try await WatchTurnRunner.run(question: "put milk on my shopping list")

        #expect(reply == "Milk added.")
        let chat = try watchChat(in: container)
        #expect(chat.messages.count == 2)
        #expect(chat.messages.map(\.role) == ["user", "assistant"])
        // The chat is titled up front — generation has nothing to do here.
        #expect(chat.title == Localized.Watch.chatTitle)
    }

    @Test("a follow-up turn joins the same chat")
    @MainActor func followUpJoinsSameChat() async throws {
        let (agent, provider, container) = try makeContainer()
        let service = FakeChatService()
        service.enqueueEventStream([.contentDelta("First."), .finished(.stop)])
        service.enqueueEventStream([.contentDelta("Second."), .finished(.stop)])
        registerServices(container: container, chatService: service)
        UserDefaults.standard.removeObject(forKey: StorageKey.watchChat)
        defer { UserDefaults.standard.removeObject(forKey: StorageKey.watchChat) }

        _ = try await WatchTurnRunner.run(question: "first question")
        let chat = try watchChat(in: container)
        _ = try await WatchTurnRunner.run(question: "what did I just ask?")

        #expect(try watchChat(in: container).id == chat.id)
        #expect(try watchChat(in: container).messages.count == 4)
    }

    @Test("a failed turn throws, keeps the question, and persists no reply")
    @MainActor func failedTurnThrows() async throws {
        let (agent, provider, container) = try makeContainer()
        let service = FakeChatService()
        service.throwOnEventStream(URLError(.cannotConnectToHost))
        registerServices(container: container, chatService: service)
        UserDefaults.standard.removeObject(forKey: StorageKey.watchChat)
        defer { UserDefaults.standard.removeObject(forKey: StorageKey.watchChat) }

        await #expect(throws: URLError.self) {
            try await WatchTurnRunner.run(question: "anything")
        }

        // The spoken question stays as history; only the reply is withheld.
        let context = try WatchAgentContext.resolve()
        #expect(context.messages.map(\.role) == ["user"])
    }

    @Test("an abandoned turn persists its fragments but yields no reply")
    @MainActor func abandonedTurnPersistsNoReply() async throws {
        let (agent, provider, container) = try makeContainer()
        let service = FakeChatService()
        service.enqueueEventStream([
            .contentDelta("Okay, I'm going to look that up."), .finished(.stop),
        ])
        registerServices(container: container, chatService: service)
        UserDefaults.standard.removeObject(forKey: StorageKey.watchChat)
        defer { UserDefaults.standard.removeObject(forKey: StorageKey.watchChat) }

        await #expect(throws: CancellationError.self) {
            try await WatchTurnRunner.run(
                question: "do the slow thing", isAbandoned: { true }
            )
        }

        // The work did happen: narration and tool results stay in the chat as
        // context for the next message. Only the wrist keeps silent — the
        // give-up message reads on its own.
        let context = try WatchAgentContext.resolve()
        #expect(context.messages.map(\.role) == ["user", "assistant"])
        #expect(context.messages.last?.content == "Okay, I'm going to look that up.")
    }

    @Test("permission prompting is disabled for a pocketed phone")
    @MainActor func promptingDisabled() throws {
        let (agent, provider, container) = try makeContainer()
        registerServices(
            container: container, chatService: FakeChatService()
        )
        UserDefaults.standard.removeObject(forKey: StorageKey.watchChat)
        defer { UserDefaults.standard.removeObject(forKey: StorageKey.watchChat) }

        let context = try WatchAgentContext.resolve()

        #expect(context.agent.id == agent.id)
        #expect(context.provider.id == provider.id)
        #expect(context.permissionPolicy.canPromptUser == false)
    }
}
