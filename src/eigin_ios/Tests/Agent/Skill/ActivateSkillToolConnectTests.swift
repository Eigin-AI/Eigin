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
    private let connectionGate = SkillConnectionGate()
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
        connectionGate.beginUserTurn(chatID: chat.id, messageID: UUID().uuidString)
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
            capabilityDeclines: declines,
            connectionGate: connectionGate,
            userMessageID: connectionGate.messageID(chatID: chat.id)
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

    private func requestAndReply(chat: Chat, agent: Agent) async {
        let first = await activate("health", chat: chat, agent: agent) { _ in
            Issue.record("Initial attempt must not open a sheet")
            return .cancelled
        }
        #expect(first.content.contains("confirmation_required"))
        #expect(!chat.isSkillActive("health"))
        connectionGate.beginUserTurn(chatID: chat.id, messageID: UUID().uuidString)
    }

    @Test func initialAndSameTurnRetriesNeverOpenASheet() async throws {
        let (agent, chat, container) = try makeFixture()
        _ = container
        let asks = Asks()
        for _ in 0 ..< 3 {
            let result = await activate("health", chat: chat, agent: agent) { request in
                asks.requests.append(request)
                return .connected
            }
            #expect(result.content.contains("confirmation_required"))
        }
        #expect(asks.requests.isEmpty)
        #expect(!chat.isSkillActive("health"))
    }

    @Test func cancellationRequiresAFreshHandshake() async throws {
        let (agent, chat, container) = try makeFixture()
        _ = container
        await requestAndReply(chat: chat, agent: agent)
        let asks = Asks()
        let handler: ConnectCapabilityHandler = { request in
            asks.requests.append(request)
            return .cancelled
        }
        let cancelled = await activate("health", chat: chat, agent: agent, handler: handler)
        #expect(cancelled.content.contains("stopped"))
        _ = await activate("health", chat: chat, agent: agent, handler: handler)
        #expect(asks.requests.count == 1)
        #expect(!declines.isDeclined(.health))
        #expect(!chat.isSkillActive("health"))
        connectionGate.beginUserTurn(chatID: chat.id, messageID: UUID().uuidString)
        let fresh = await activate("health", chat: chat, agent: agent, handler: handler)
        #expect(fresh.content.contains("confirmation_required"))
        #expect(asks.requests.count == 1)
    }

    @Test func unknownUserBoundaryCannotOpenASheet() async throws {
        let (agent, chat, container) = try makeFixture()
        _ = container
        let asks = Asks()
        let tool = ActivateSkillTool(chatID: chat.id, onConnectCapability: { request in
            asks.requests.append(request)
            return .connected
        }, capabilityDeclines: declines, connectionGate: SkillConnectionGate())
        let result = await tool.execute(ToolCall(
            id: "unknown", type: "function",
            function: .init(
                name: "activate_skill",
                arguments: #"{"skill_id":"health","confirm":true}"#
            )
        ), agent: agent)
        #expect(result.content.contains("confirmation_required"))
        #expect(asks.requests.isEmpty)
    }

    @Test func incompleteConnectionCannotImmediatelyReopenTheSheet() async throws {
        let (agent, chat, container) = try makeFixture()
        _ = container
        await requestAndReply(chat: chat, agent: agent)
        let asks = Asks()
        let handler: ConnectCapabilityHandler = { request in
            asks.requests.append(request)
            return .connected
        }
        let result = await activate("health", chat: chat, agent: agent, handler: handler)
        #expect(result.content.contains("still need"))
        _ = await activate("health", chat: chat, agent: agent, handler: handler)
        #expect(asks.requests.count == 1)
        #expect(!chat.isSkillActive("health"))
    }

    @Test func staleActiveSkillStillRequiresAReply() async throws {
        let (agent, chat, container) = try makeFixture()
        _ = container
        SkillActivation.activate(skillID: "health", on: chat, activatingToolCallID: "old")
        let result = await activate("health", chat: chat, agent: agent) { _ in
            Issue.record("Stale skill must not bypass confirmation")
            return .connected
        }
        #expect(result.content.contains("confirmation_required"))
        #expect(!chat.isSkillActive("health"))
    }

    @Test func delayedToolConstructionCannotBorrowANewerUserReply() async throws {
        let (agent, chat, container) = try makeFixture()
        _ = container
        let initiatingMessage = connectionGate.messageID(chatID: chat.id)
        _ = await activate("health", chat: chat, agent: agent) { _ in .cancelled }
        connectionGate.beginUserTurn(chatID: chat.id, messageID: UUID().uuidString)
        // A registry rebuilt for the old turn must retain its initiating boundary.
        let tool = ActivateSkillTool(
            chatID: chat.id,
            onConnectCapability: { _ in
                Issue.record("An old turn must not consume a newer reply")
                return .cancelled
            },
            capabilityDeclines: declines,
            connectionGate: connectionGate,
            userMessageID: initiatingMessage
        )
        let result = await tool.execute(ToolCall(
            id: "delayed", type: "function",
            function: .init(name: "activate_skill", arguments: #"{"skill_id":"health"}"#)
        ), agent: agent)
        #expect(result.content.contains("confirmation_required"))
    }

    @Test func aPendingRequestDoesNotAuthorizeAnotherChat() async throws {
        let (agent, chat, container) = try makeFixture()
        await requestAndReply(chat: chat, agent: agent)
        let other = Chat(agentID: agent.id)
        container.mainContext.insert(other)
        connectionGate.beginUserTurn(chatID: other.id, messageID: UUID().uuidString)
        let result = await activate("health", chat: other, agent: agent) { _ in
            Issue.record("Another chat needs its own handshake")
            return .connected
        }
        #expect(result.content.contains("confirmation_required"))
        #expect(!other.isSkillActive("health"))
    }

    @Test func connectingActivatesTheSkill() async throws {
        let (agent, chat, container) = try makeFixture()
        await requestAndReply(chat: chat, agent: agent)
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

    /// Health gates on capability, not requiredTools — the result must name
    /// the tools the integration actually provides, not an empty list the
    /// model would read as the activation failing (#296).
    @Test func activationReportsTheToolsTheSkillUnlocks() async throws {
        let (agent, chat, container) = try makeFixture()
        await requestAndReply(chat: chat, agent: agent)

        let result = await activate("health", chat: chat, agent: agent) { _ in
            container.mainContext.insert(Integration(
                typeID: "apple-health",
                accountLabel: "",
                grantedCapabilities: [Capability.health.rawValue]
            ))
            return .connected
        }

        let available = try #require(activationResult(of: result)?["tools_available"] as? [String])
        #expect(Set(available) == Set(HealthToolKit.tools(context: ToolContext()).map(\.name)))
    }

    /// An optional capability contributes its tools only when something
    /// actually provides it: planning's connected calendar adds calendar
    /// tools, its unconnected reminders add none.
    @Test func optionalCapabilityToolsFollowTheConnection() async throws {
        let (agent, chat, container) = try makeFixture()
        container.mainContext.insert(Integration(
            typeID: "apple-calendar",
            accountLabel: "",
            grantedCapabilities: [Capability.calendar.rawValue]
        ))

        let result = await activate("planning", chat: chat, agent: agent, handler: nil)

        let available = try #require(activationResult(of: result)?["tools_available"] as? [String])
        #expect(available.contains("start_flow"))
        #expect(available.contains("get_calendar_events"))
        #expect(!available.contains("get_reminders"))
    }

    /// A tool the user set to "never" must not be reported as available —
    /// the registry excludes it, so calling it would fail.
    @Test func neverPermissionedToolsAreNotReported() async throws {
        let (agent, chat, container) = try makeFixture()
        container.mainContext.insert(AgentToolGrant(
            agentID: agent.id,
            capability: LogFoodTool.capability,
            level: .never
        ))
        container.mainContext.insert(Integration(
            typeID: "apple-health",
            accountLabel: "",
            grantedCapabilities: [Capability.health.rawValue]
        ))

        let result = await activate("health", chat: chat, agent: agent, handler: nil)

        let available = try #require(activationResult(of: result)?["tools_available"] as? [String])
        #expect(!available.contains("log_food"))
        #expect(available.contains("get_health_log"))
    }

    /// Same for an already-connected capability — no ask, straight activate.
    @Test func connectedSkillActivationReportsItsTools() async throws {
        let (agent, chat, container) = try makeFixture()
        container.mainContext.insert(Integration(
            typeID: "apple-health",
            accountLabel: "",
            grantedCapabilities: [Capability.health.rawValue]
        ))

        let result = await activate("health", chat: chat, agent: agent) { _ in .connected }

        let available = try #require(activationResult(of: result)?["tools_available"] as? [String])
        #expect(available.contains("search_food"))
    }

    /// The JSON `result` dictionary of a successful activation, or nil.
    private func activationResult(of result: ToolResult) -> [String: Any]? {
        ToolHelpers.parseArguments(result.content)?["result"] as? [String: Any]
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
        await requestAndReply(chat: chat, agent: agent)
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
