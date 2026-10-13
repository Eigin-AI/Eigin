@testable import Eigin
import Factory
import Foundation
import SwiftData
import Testing

/// Activating a skill whose capability isn't connected: it asks once, carries
/// on with the skill when connected, and without it otherwise.
@Suite("ActivateSkillTool - connecting a capability", .serialized)
@MainActor
struct ActivateSkillToolConnectTests {
    private let declines = DeclinedCapabilities(defaults: .isolated())
    private let calendarService = FakeCalendarService()
    private let reminderService = FakeReminderService()

    init() {
        Container.shared.reset()
        Container.shared.integrationManager.register {
            @MainActor in IntegrationManager(
                oauthService: FakeIntegrationOAuthService(),
                imapCredentialStore: FakeIMAPCredentialStore(),
                aulaCredentialStore: FakeAulaCredentialStore()
            )
        }
        Container.shared.healthService.register { FakeHealthService() }
        let calendarService = calendarService
        let reminderService = reminderService
        Container.shared.calendarService.register { calendarService }
        Container.shared.reminderService.register { reminderService }
    }

    /// What the handler was asked, recorded from a sendable closure.
    @MainActor private final class Asks {
        var requests: [CapabilityRequest] = []
    }

    private func makeFixture() throws -> (Agent, Chat, ModelContainer) {
        let container = try ModelContainer(
            for: Schema(SchemaV10.models, version: SchemaV10.versionIdentifier),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let agent = Agent(name: "Wren", providerID: UUID(), model: "test-model")
        container.mainContext.insert(agent)
        let chat = Chat(agentID: agent.id)
        container.mainContext.insert(chat)
        return (agent, chat, container)
    }

    private func activate(
        _ skillID: String,
        chat: Chat,
        agent: Agent,
        handler: ConnectCapabilityHandler?
    ) async -> ToolResult {
        let tool = ActivateSkillTool(
            chatID: chat.id,
            onConnectCapability: handler,
            capabilityDeclines: declines
        )
        return await tool.execute(
            ToolCall(
                id: "call_\(UUID().uuidString)",
                type: "function",
                function: .init(name: "activate_skill", arguments: #"{"skill_id": "\#(skillID)"}"#)
            ),
            agent: agent
        )
    }

    @Test func connectingActivatesTheSkill() async throws {
        let (agent, chat, container) = try makeFixture()
        let asks = Asks()

        let result = await activate("health", chat: chat, agent: agent) { request in
            asks.requests.append(request)
            // What the connect sheet does once iOS allows it.
            container.mainContext.insert(Integration(
                typeID: "apple-health",
                accountLabel: "",
                grantedCapabilities: [Capability.health.rawValue]
            ))
            return .connected
        }

        #expect(!result.isError)
        #expect(chat.isSkillActive("health"))
        #expect(asks.requests.first?.capabilities == [.health])
        #expect(asks.requests.first?.providerIDs == ["apple-health"])
        #expect(asks.requests.first?.agentName == "Wren")
    }

    @Test func aConnectedCapabilityActivatesWithoutAsking() async throws {
        let (agent, chat, container) = try makeFixture()
        container.mainContext.insert(Integration(
            typeID: "apple-health",
            accountLabel: "",
            grantedCapabilities: [Capability.health.rawValue]
        ))
        let asks = Asks()

        _ = await activate("health", chat: chat, agent: agent) { request in
            asks.requests.append(request)
            return .connected
        }

        #expect(chat.isSkillActive("health"))
        #expect(asks.requests.isEmpty)
    }

    @Test func notNowIsRememberedSoItAsksOnce() async throws {
        let (agent, chat, container) = try makeFixture()
        _ = container
        let asks = Asks()
        let handler: ConnectCapabilityHandler = { request in
            asks.requests.append(request)
            return .declined
        }

        let first = await activate("health", chat: chat, agent: agent, handler: handler)
        let second = await activate("health", chat: chat, agent: agent, handler: handler)

        #expect(!first.isError)
        #expect(!chat.isSkillActive("health"))
        #expect(declines.isDeclined(.health))
        #expect(asks.requests.count == 1)
        #expect(second.content.contains("declined"))
    }

    @Test func withoutAnyoneToAskItDeclinesWithoutRemembering() async throws {
        let (agent, chat, container) = try makeFixture()
        _ = container

        let result = await activate("health", chat: chat, agent: agent, handler: nil)

        #expect(!result.isError)
        #expect(!chat.isSkillActive("health"))
        #expect(!declines.isDeclined(.health))
    }

    @Test func whenIOSHasRefusedEveryProviderItDoesNotAsk() async throws {
        let (agent, chat, container) = try makeFixture()
        _ = container
        calendarService.accessLevel = .none
        let asks = Asks()

        let result = await activate("calendar", chat: chat, agent: agent) { request in
            asks.requests.append(request)
            return .connected
        }

        #expect(asks.requests.isEmpty)
        #expect(!chat.isSkillActive("calendar"))
        #expect(result.content.contains("turned off"))
        #expect(!declines.isDeclined(.calendar))
    }

    @Test func connectingAgainClearsAnEarlierNo() async throws {
        let (agent, chat, container) = try makeFixture()
        declines.decline(.calendar)
        declines.decline(.reminders)

        // Adding it in Connections after saying no in a chat.
        let connectedManager = IntegrationManager(
            oauthService: FakeIntegrationOAuthService(),
            imapCredentialStore: FakeIMAPCredentialStore(),
            aulaCredentialStore: FakeAulaCredentialStore(),
            declines: declines
        )
        connectedManager.connectPlatform(
            BundledIntegrationType.appleCalendar,
            in: container.mainContext
        )

        let result = await activate("calendar", chat: chat, agent: agent, handler: nil)

        #expect(!declines.isDeclined(.calendar))
        #expect(!result.isError)
        #expect(chat.isSkillActive("calendar"))
    }
}
