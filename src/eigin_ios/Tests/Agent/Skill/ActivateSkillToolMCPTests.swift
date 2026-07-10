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

    init() {
        Container.shared.reset()
        Container.shared.mcpServerManager.register {
            MCPServerManager(
                keychainService: PreviewKeychainService(),
                oauthService: PreviewMCPOAuthService()
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

    @Test @MainActor func alreadyActiveSkillErrorsBeforeAttemptingConnection() async throws {
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
        #expect(result.content.contains("already active"))
    }
}
