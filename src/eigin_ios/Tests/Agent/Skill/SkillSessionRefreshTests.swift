@testable import Eigin
import Factory
import Foundation
import SwiftData
import Testing

@Suite("Skill session refresh", .serialized)
@MainActor
struct SkillSessionRefreshTests {
    init() {
        Container.shared.reset()
        Container.shared.knowledgeService.register { PreviewKnowledgeService() }
        Container.shared.intentService.register { PreviewIntentService() }
        Container.shared.calendarService.register { FakeCalendarService() }
    }

    private func fixture() throws -> (ModelContainer, Agent, Provider, Chat, ChatViewModel) {
        let container = try ModelContainer(
            for: Schema(SchemaV10.models, version: SchemaV10.versionIdentifier),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let provider = Provider(name: "Test", baseURL: "https://model.test")
        let agent = Agent(name: "Wren", providerID: provider.id, model: "test")
        agent.bootstrapComplete = true
        agent.identityCore = "Wren"
        let chat = Chat(agentID: agent.id)
        chat.title = "Skills"
        chat.titleOrigin = .edited
        container.mainContext.insert(provider)
        container.mainContext.insert(agent)
        container.mainContext.insert(chat)
        let vm = ChatViewModel(chatID: chat.id)
        vm.setUp(modelContext: container.mainContext)
        vm.chat = chat
        vm.gatekeeper = Gatekeeper(
            proactivity: agent.proactivity,
            knowledgeService: PreviewKnowledgeService()
        )
        vm.messageText = "Check current information"
        return (container, agent, provider, chat, vm)
    }

    private func call(_ name: String, _ arguments: String = "{}") -> ToolCall {
        ToolCall(
            id: UUID().uuidString,
            type: "function",
            function: .init(name: name, arguments: arguments)
        )
    }

    @Test func providerSwapBetweenRoundsUsesNewAccount() async throws {
        let (container, agent, provider, _, vm) = try fixture()
        let first = Integration(
            typeID: "aula",
            accountLabel: "First",
            grantedCapabilities: [Capability.aula.rawValue]
        )
        let second = Integration(
            typeID: "aula",
            accountLabel: "Second",
            grantedCapabilities: [Capability.aula.rawValue]
        )
        container.mainContext.insert(first)
        container.mainContext.insert(second)
        let store = FakeAulaCredentialStore()
        for (integration, name) in [(first, "FirstChild"), (second, "SecondChild")] {
            store.save(AulaSession(
                accessToken: "stored", refreshToken: nil, expiresAt: nil, cookies: [:],
                apiVersion: 24,
                children: [AulaChild(id: name, name: name, institution: "School")]
            ), for: integration.id)
        }
        Container.shared.aulaCredentialStore.register { store }
        let manager = Container.shared.integrationManager()
        manager.setActiveProvider(first, for: .aula, in: container.mainContext)
        container.mainContext.insert(AgentToolGrant(
            agentID: agent.id,
            capability: GetAulaChildrenTool.capability,
            level: .always
        ))
        let service = ObservedChatService { round, _, _ in
            if round ==
                1 { manager.setActiveProvider(second, for: .aula, in: container.mainContext) }
        }
        Container.shared.chatService.register { service }
        service.scripted.enqueueEventStream([
            .toolCall(call("activate_skill", #"{"skill_id":"aula"}"#)),
            .finished(.toolCalls),
        ])
        service.scripted.enqueueEventStream([
            .toolCall(call("read_core", #"{"core":"identity"}"#)),
            .finished(.toolCalls),
        ])
        service.scripted.enqueueEventStream([
            .toolCall(call("aula_children")),
            .finished(.toolCalls),
        ])
        service.scripted.enqueueEventStream([.contentDelta("Checked."), .finished(.stop)])
        vm.send(agent: agent, provider: provider, space: nil, spaces: [], mcpServers: [])
        await vm.streamTask?.value
        #expect(vm.chatError == nil)
        #expect(vm.window.messages
            .contains { $0.role == "tool" && $0.content?.contains("SecondChild") == true })
        #expect(!vm.window.messages
            .contains { $0.role == "tool" && $0.content?.contains("FirstChild") == true })
    }

    @Test func disablingOptionalIntegrationRemovesItsToolsBetweenRounds() async throws {
        let (container, agent, provider, _, vm) = try fixture()
        let integration = Integration(
            typeID: "apple-calendar",
            accountLabel: "",
            grantedCapabilities: [Capability.calendar.rawValue]
        )
        container.mainContext.insert(integration)
        container.mainContext.insert(AgentToolGrant(
            agentID: agent.id,
            capability: GetCalendarEventsTool.capability,
            level: .always
        ))
        let service = ObservedChatService { round, _, tools in
            let names = Set(tools.map(\.function.name))
            if round == 1 {
                #expect(names.contains("get_calendar_events"))
                integration.isEnabled = false
            }
            if round == 2 { #expect(!names.contains("get_calendar_events")) }
        }
        Container.shared.chatService.register { service }
        let rejected = call("get_calendar_events")
        service.scripted.enqueueEventStream([
            .toolCall(call("activate_skill", #"{"skill_id":"planning"}"#)),
            .finished(.toolCalls),
        ])
        service.scripted.enqueueEventStream([
            .toolCall(call("read_core", #"{"core":"identity"}"#)),
            .finished(.toolCalls),
        ])
        service.scripted.enqueueEventStream([.toolCall(rejected), .finished(.toolCalls)])
        service.scripted.enqueueEventStream([.contentDelta("Unavailable."), .finished(.stop)])
        vm.send(agent: agent, provider: provider, space: nil, spaces: [], mcpServers: [])
        await vm.streamTask?.value
        #expect(vm.chatError == nil)
        #expect(vm.window.messages
            .contains {
                $0.toolCallID == rejected.id && $0.content?.contains("Unknown tool") == true
            })
    }

    @Test func persistedMCPActivationRefreshesFirstRequestToolsAndInstructions() async throws {
        let (container, agent, provider, chat, vm) = try fixture()
        let server = MCPServer(name: "GitLab", url: "https://gitlab.test/mcp", authType: .oauth)
        server.cachedToolNames = ["obsolete_tool"]
        server.serverInstructions = "Obsolete server instructions."
        container.mainContext.insert(server)
        SkillActivation.activate(skillID: "mcp__gitlab", on: chat, activatingToolCallID: "previous")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [InitiativeMCPProtocol.self]
        let manager = MCPServerManager(
            keychainService: PreviewKeychainService(),
            oauthService: StoredBackgroundMCPAuth(),
            httpConfiguration: configuration
        )
        Container.shared.mcpServerManager.register { manager }
        let service = ObservedChatService { round, messages, tools in
            guard round == 0 else { return }
            #expect(tools.contains { $0.function.name == "mcp__gitlab__list_issues" })
            #expect(!tools.contains { $0.function.name == "mcp__gitlab__obsolete_tool" })
            #expect(messages.contains { $0.content?.contains("Use current GitLab data.") == true })
            #expect(!messages
                .contains { $0.content?.contains("Obsolete server instructions.") == true })
        }
        Container.shared.chatService.register { service }
        service.scripted.enqueueEventStream([.contentDelta("Ready."), .finished(.stop)])
        vm.send(agent: agent, provider: provider, space: nil, spaces: [], mcpServers: [server])
        await vm.streamTask?.value
        #expect(vm.chatError == nil)
    }

    @Test func maintenanceDiscoveryKeepsMCPOutOfCatalog() async throws {
        let (container, agent, _, _, _) = try fixture()
        container.mainContext.insert(MCPServer(name: "GitLab", url: "https://gitlab.test/mcp"))
        Container.shared.skillIndex.register {
            SkillIndex { text in text.lowercased().contains("gitlab") ? [1.0, 0.0] : [0.0, 1.0] }
        }
        let registry = ToolRegistry.background(onSignal: { _ in })
        let result = await registry.execute(
            call("search_skills", #"{"query":"GitLab"}"#),
            agent: agent
        )
        #expect(!result.isError)
        #expect(!result.content.contains("mcp__gitlab"))
        #expect(result.content.contains("No matching skills"))
    }
}
