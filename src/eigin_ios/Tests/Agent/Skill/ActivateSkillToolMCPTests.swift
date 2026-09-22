@testable import Eigin
import Factory
import Foundation
import SwiftData
import Testing

@Suite("ActivateSkillTool - MCP servers", .serialized)
struct ActivateSkillToolMCPTests {
    // MARK: - Helpers

    @MainActor
    private func makeFixture() throws -> (Agent, Chat, ModelContainer) {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Schema(SchemaV6.models, version: SchemaV6.versionIdentifier),
            configurations: config
        )
        let agent = Agent(name: "TestAgent", providerID: UUID(), model: "test-model")
        container.mainContext.insert(agent)
        let chat = Chat(agentID: agent.id)
        container.mainContext.insert(chat)
        return (agent, chat, container)
    }

    private func makeCall(arguments: String) -> ToolCall {
        ToolCall(
            id: "call_activate_\(UUID().uuidString)",
            type: "function",
            function: .init(name: "activate_skill", arguments: arguments)
        )
    }

    @MainActor init() {
        Container.shared.reset()
        Container.shared.mcpServerManager.register {
            MCPServerManager(
                keychainService: PreviewKeychainService(),
                oauthService: PreviewMCPOAuthService()
            )
        }
        Container.shared.integrationManager.register {
            @MainActor in IntegrationManager(
                oauthService: FakeIntegrationOAuthService(),
                imapCredentialStore: FakeIMAPCredentialStore(),
                aulaCredentialStore: FakeAulaCredentialStore()
            )
        }
    }

    // MARK: - Tests

    @Test @MainActor func unknownSkillIDErrors() async throws {
        let (agent, chat, container) = try makeFixture()
        _ = container
        let tool = ActivateSkillTool(chatID: chat.id)

        let result = await tool.execute(
            makeCall(arguments: #"{"skill_id": "mcp__nonexistent"}"#),
            agent: agent
        )

        #expect(result.isError)
        #expect(!chat.isSkillActive("mcp__nonexistent"))
    }

    @Test @MainActor func connectionFailureReturnsErrorAndDoesNotActivate() async throws {
        let (agent, chat, container) = try makeFixture()
        // Empty URL deterministically fails to parse — no network involved.
        let server = MCPServer(name: "Broken", url: "")
        container.mainContext.insert(server)

        let tool = ActivateSkillTool(chatID: chat.id)
        let result = await tool.execute(
            makeCall(arguments: #"{"skill_id": "mcp__broken"}"#),
            agent: agent
        )

        #expect(result.isError)
        #expect(!chat.isSkillActive("mcp__broken"))
        #expect(result.content.contains("Broken"))
    }

    @Test @MainActor func disabledServerIsNotActivatable() async throws {
        let (agent, chat, container) = try makeFixture()
        let server = MCPServer(name: "Disabled", url: "https://example.com", isEnabled: false)
        container.mainContext.insert(server)

        let tool = ActivateSkillTool(chatID: chat.id)
        let result = await tool.execute(
            makeCall(arguments: #"{"skill_id": "mcp__disabled"}"#),
            agent: agent
        )

        #expect(result.isError)
        #expect(!chat.isSkillActive("mcp__disabled"))
    }

    @Test @MainActor func alreadyActiveMCPSkillStillAttemptsReconnection() async throws {
        // #262: re-activating an active skill must attempt to heal it (fresh
        // connection) rather than short-circuiting on "already active" —
        // otherwise a chat with drifted skill/tool state has no recovery path.
        let (agent, chat, container) = try makeFixture()
        let server = MCPServer(name: "Broken", url: "")
        container.mainContext.insert(server)
        chat.activeSkillEntries.append(
            ActiveSkillEntry(
                skillID: "mcp__broken",
                activatedAt: .now,
                activatingToolCallID: "earlier"
            )
        )

        let tool = ActivateSkillTool(chatID: chat.id)
        let result = await tool.execute(
            makeCall(arguments: #"{"skill_id": "mcp__broken"}"#),
            agent: agent
        )

        #expect(result.isError)
        #expect(!result.content.contains("already active"))
        #expect(result.content.contains("Broken"))
        // Activation failed, so the existing entry stays.
        #expect(chat.isSkillActive("mcp__broken"))
    }

    @Test @MainActor func alreadyActiveBundledSkillReactivatesInsteadOfErroring() async throws {
        let (agent, chat, container) = try makeFixture()
        container.mainContext.insert(Integration(
            typeID: "google",
            accountLabel: "test@gmail.com",
            grantedCapabilities: [Capability.email.rawValue]
        ))
        chat.activeSkillEntries.append(
            ActiveSkillEntry(skillID: "email", activatedAt: .now, activatingToolCallID: "earlier")
        )

        let tool = ActivateSkillTool(chatID: chat.id)
        let result = await tool.execute(
            makeCall(arguments: #"{"skill_id": "email"}"#),
            agent: agent
        )

        #expect(!result.isError)
        #expect(result.content.contains("email"))
        #expect(chat.isSkillActive("email"))
        #expect(chat.activeSkillEntries.count(where: { $0.skillID == "email" }) == 1)
    }

    @Test @MainActor func staleEntryWithMissingCapabilityIsClearedWithActionableError(
    ) async throws {
        // #262: skill says active, but no connected provider supplies the
        // capability anymore — the stale entry must be dropped so a later
        // activation can succeed, and the error must name the capability.
        let (agent, chat, container) = try makeFixture()
        _ = container
        chat.activeSkillEntries.append(
            ActiveSkillEntry(skillID: "email", activatedAt: .now, activatingToolCallID: "earlier")
        )

        let tool = ActivateSkillTool(chatID: chat.id)
        let result = await tool.execute(
            makeCall(arguments: #"{"skill_id": "email"}"#),
            agent: agent
        )

        #expect(result.isError)
        #expect(result.content.contains("no connected provider"))
        #expect(!chat.isSkillActive("email"))
    }

    @Test @MainActor func staleEntryReactivatesOnceProviderReturns() async throws {
        // With the integration disabled the stale entry is dropped; once the
        // provider comes back, activation succeeds again — no perma-dead-end.
        let (agent, chat, container) = try makeFixture()
        let integration = Integration(
            typeID: "google",
            accountLabel: "test@gmail.com",
            grantedCapabilities: [Capability.email.rawValue],
            isEnabled: false
        )
        container.mainContext.insert(integration)
        chat.activeSkillEntries.append(
            ActiveSkillEntry(skillID: "email", activatedAt: .now, activatingToolCallID: "earlier")
        )

        let tool = ActivateSkillTool(chatID: chat.id)
        let result = await tool.execute(
            makeCall(arguments: #"{"skill_id": "email"}"#),
            agent: agent
        )
        #expect(result.isError)

        // User re-enables the provider: reactivation now succeeds.
        integration.isEnabled = true
        let recovered = await tool.execute(
            makeCall(arguments: #"{"skill_id": "email"}"#),
            agent: agent
        )
        #expect(!recovered.isError)
        #expect(chat.isSkillActive("email"))
    }
}
