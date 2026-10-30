@testable import Eigin
import Factory
import Foundation
import SwiftData
import Testing

@Suite("Shared skill activation", .serialized)
@MainActor
struct SkillSessionTests {
    init() {
        Container.shared.reset()
        Container.shared.knowledgeService.register { PreviewKnowledgeService() }
        Container.shared.intentService.register { PreviewIntentService() }
        Container.shared.integrationManager.register {
            @MainActor in IntegrationManager(
                oauthService: FakeIntegrationOAuthService(),
                imapCredentialStore: FakeIMAPCredentialStore(),
                aulaCredentialStore: FakeAulaCredentialStore()
            )
        }
    }

    private func fixture() throws -> (ModelContainer, Agent, Chat) {
        let container = try ModelContainer(
            for: Schema(SchemaV10.models, version: SchemaV10.versionIdentifier),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let agent = Agent(name: "Wren", providerID: UUID(), model: "test")
        let chat = Chat(agentID: agent.id)
        container.mainContext.insert(agent)
        container.mainContext.insert(chat)
        return (container, agent, chat)
    }

    private func session(
        agent: Agent,
        policy: any ToolPermissionPolicy = AlwaysAllowPolicy()
    ) -> SkillSession {
        SkillSession(
            toolAccess: .unattended,
            permissionPolicy: policy,
            accessPolicy: SpaceAccessPolicy(currentSpaceID: nil, publicSpaceIDs: []),
            agentID: agent.id
        )
    }

    private func call(_ name: String, arguments: String = "{}") -> ToolCall {
        ToolCall(
            id: UUID().uuidString,
            type: "function",
            function: .init(name: name, arguments: arguments)
        )
    }

    @Test func activatesWithoutChatAndDoesNotPersistOrLeak() async throws {
        let (container, agent, chat) = try fixture()
        let state = session(agent: agent)
        let registry = ToolRegistry.background(skillSession: state, onSignal: { _ in })
        let result = await registry.execute(
            call("activate_skill", arguments: #"{"skill_id":"self_modification"}"#),
            agent: agent
        )

        #expect(!result.isError)
        let payload = try #require(JSONSerialization
            .jsonObject(with: Data(result.content.utf8)) as? [String: Any])
        let activated = try #require(payload["result"] as? [String: Any])
        #expect(activated["instruction"] as? String == BundledSkill.selfModification.instruction)
        #expect(state.activeSkills.map(\.id) == ["self_modification"])
        #expect(chat.activeSkillEntries.isEmpty)
        #expect(!state.candidates(context: container.mainContext)
            .contains { $0.id == "self_modification" })
        #expect(session(agent: agent).activeSkills.isEmpty)
    }

    @Test func missingIntegrationNeverCallsConnectionHandler() async throws {
        let (container, agent, chat) = try fixture()
        defer { _ = container }
        let state = session(agent: agent)
        let tool = ActivateSkillTool(skillSession: state, onConnectCapability: { _ in
            Issue.record("Background activation must not request a connection")
            return .declined
        })
        let result = await tool.execute(
            call("activate_skill", arguments: #"{"skill_id":"email"}"#),
            agent: agent
        )
        #expect(result.isError)
        #expect(state.activeSkills.isEmpty)
        #expect(chat.activeSkillEntries.isEmpty)
    }

    @Test func connectedIntegrationAddsOnlyAlwaysToolsAfterActivation() async throws {
        let (container, agent, chat) = try fixture()
        let provider = try #require(BundledIntegrationType.all
            .first { $0.providedCapabilities.contains(.email) })
        container.mainContext.insert(Integration(
            typeID: provider.id, accountLabel: "test",
            grantedCapabilities: [Capability.email.rawValue]
        ))
        let available = try Container.shared.integrationManager().toolsByCapability(
            integrations: container.mainContext.fetch(FetchDescriptor<Integration>()),
            selections: [], context: ToolContext(canPromptUser: false)
        )[.email] ?? []
        try #require(available.count >= 3)
        let allowed = try #require(available.first?.name)
        let asked = available[1].name
        let denied = available[2].name
        let policy = AgentPermissionPolicy(
            builtInGrants: [allowed: .always, asked: .ask, denied: .never],
            discoveredGrants: [:], chatGrants: [], canPromptUser: false
        )
        let state = session(agent: agent, policy: policy)
        #expect(state.tools().isEmpty)
        let result = await state.activate(skillID: "email", agent: agent, toolCallID: "activate")
        #expect(!result.isError)
        let tools = state.tools()
        #expect(tools.allSatisfy { policy.permissionLevel(for: $0.name) == .always })
        #expect(tools.contains { $0.name == allowed })
        #expect(!tools.contains { $0.name == asked || $0.name == denied })
        let rebuilt = ToolRegistry.background(
            permissionPolicy: policy, additionalTools: tools, skillSession: state,
            onSignal: { _ in }
        )
        let names = Set(rebuilt.definitions.map(\.function.name))
        #expect(tools.allSatisfy { names.contains($0.name) })
        for name in [asked, denied] {
            let rejected = await rebuilt.execute(call(name), agent: agent)
            #expect(rejected.isError)
            #expect(rejected.content.contains("Unknown tool"))
        }
        #expect(chat.activeSkillEntries.isEmpty)
    }

    @Test func searchFindsMCPWithoutChat() async throws {
        let (container, agent, _) = try fixture()
        container.mainContext.insert(MCPServer(name: "GitLab", url: "https://example.com"))
        let state = session(agent: agent)
        let index = SkillIndex { text in text.lowercased().contains("gitlab") ? [1.0, 0.0] : [
            0.0,
            1.0,
        ] }
        let tool = SearchSkillsTool(skillSession: state, skillIndex: index)
        let result = await tool.execute(
            call("search_skills", arguments: #"{"query":"GitLab"}"#),
            agent: agent
        )
        #expect(!result.isError)
        #expect(result.content.contains("mcp__gitlab"))
        #expect(!result.content.contains("asks the user"))
    }

    @Test func failedMCPConnectionDoesNotActivateOrAuthorize() async throws {
        let (container, agent, _) = try fixture()
        let auth = BackgroundMCPAuth()
        Container.shared.mcpServerManager.register {
            MCPServerManager(keychainService: PreviewKeychainService(), oauthService: auth)
        }
        container.mainContext.insert(MCPServer(
            name: "GitLab",
            url: "https://example.com",
            authType: .oauth
        ))
        let state = session(agent: agent)
        let result = await state.activate(
            skillID: "mcp__gitlab",
            agent: agent,
            toolCallID: "activate"
        )
        #expect(result.isError)
        #expect(state.activeSkills.isEmpty)
        #expect(state.tools().isEmpty)
    }

    @Test func missingStoredCredentialsPreventActivation() async throws {
        for typeID in ["google", "imap", "aula"] {
            let (container, agent, _) = try fixture()
            let oauth = FakeIntegrationOAuthService()
            oauth.token = nil
            Container.shared.integrationManager.register {
                @MainActor in IntegrationManager(
                    oauthService: oauth,
                    imapCredentialStore: FakeIMAPCredentialStore(),
                    aulaCredentialStore: FakeAulaCredentialStore()
                )
            }
            let capability: Capability = typeID == "aula" ? .aula : .email
            container.mainContext.insert(Integration(
                typeID: typeID, accountLabel: "test", grantedCapabilities: [capability.rawValue]
            ))
            let state = session(agent: agent)
            let result = await ActivateSkillTool(skillSession: state).execute(
                call("activate_skill", arguments: "{\"skill_id\":\"\(capability.rawValue)\"}"),
                agent: agent
            )
            #expect(result.isError)
            #expect(result.content.contains("Settings"))
            #expect(state.activeSkills.isEmpty)
            #expect(state.tools().isEmpty)
            #expect(oauth.authorizedIDs.isEmpty)
        }
    }

    @Test func unavailableOptionalIntegrationIsOmitted() async throws {
        let (container, agent, _) = try fixture()
        let calendar = FakeCalendarService()
        calendar.accessLevel = .none
        Container.shared.calendarService.register { calendar }
        container.mainContext.insert(Integration(
            typeID: "apple-calendar", accountLabel: "",
            grantedCapabilities: [Capability.calendar.rawValue]
        ))
        let state = session(agent: agent)
        let result = await ActivateSkillTool(skillSession: state).execute(
            call("activate_skill", arguments: #"{"skill_id":"planning"}"#), agent: agent
        )
        #expect(!result.isError)
        #expect(state.activeSkills.map(\.id) == ["planning"])
        #expect(state.tools().isEmpty)
    }

    @Test func writeOnlyCalendarIsUnavailableForRequiredAndOptionalUse() async throws {
        let (container, agent, _) = try fixture()
        let calendar = FakeCalendarService()
        calendar.accessLevel = .addOnly
        Container.shared.calendarService.register { calendar }
        container.mainContext.insert(Integration(
            typeID: "apple-calendar", accountLabel: "",
            grantedCapabilities: [Capability.calendar.rawValue]
        ))
        let state = session(agent: agent)
        let required = await ActivateSkillTool(skillSession: state).execute(
            call("activate_skill", arguments: #"{"skill_id":"calendar"}"#), agent: agent
        )
        #expect(required.isError)
        #expect(required.content.contains("Full access"))
        #expect(state.activeSkills.isEmpty)
        #expect(state.tools().isEmpty)

        let optional = await ActivateSkillTool(skillSession: state).execute(
            call("activate_skill", arguments: #"{"skill_id":"planning"}"#), agent: agent
        )
        #expect(!optional.isError)
        #expect(state.activeSkills.map(\.id) == ["planning"])
        #expect(state.tools().isEmpty)
    }

    @Test func initiativeLoopDiscoversActivatesAndExecutesAuthorizedMCPTools() async throws {
        let (container, agent, chat) = try fixture()
        let provider = Provider(name: "Test", baseURL: "https://model.test")
        container.mainContext.insert(provider)
        let server = MCPServer(name: "GitLab", url: "https://gitlab.test/mcp", authType: .oauth)
        server.cachedToolNames = ["list_issues"]
        container.mainContext.insert(server)
        InitiativeMCPProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [InitiativeMCPProtocol.self]
        let manager = MCPServerManager(
            keychainService: PreviewKeychainService(), oauthService: StoredBackgroundMCPAuth(),
            httpConfiguration: configuration
        )
        Container.shared.mcpServerManager.register { manager }
        Container.shared.skillIndex.register {
            SkillIndex { text in text.lowercased().contains("gitlab") ? [1.0, 0.0] : [0.0, 1.0] }
        }
        let allowed = "mcp__gitlab__list_issues"
        let excluded = [
            "mcp__gitlab__read_file",
            "mcp__gitlab__delete_issue",
            "mcp__gitlab__new_tool",
        ]
        let policy = AgentPermissionPolicy(
            builtInGrants: [:],
            discoveredGrants: [allowed: .always, excluded[0]: .ask, excluded[1]: .never],
            chatGrants: [], canPromptUser: false
        )
        let access = SpaceAccessPolicy(currentSpaceID: nil, publicSpaceIDs: [])
        let state = session(agent: agent, policy: policy)
        let signals = BackgroundSignalBox()
        let registry = ToolRegistry.background(
            accessPolicy: access, permissionPolicy: policy, agentID: agent.id,
            skillSession: state, onSignal: { signals.set($0) }
        )
        #expect(!registry.definitions.contains { $0.function.name == allowed })
        let model = FakeChatService()
        model.enqueueEventStream([
            .toolCall(call("search_skills", arguments: #"{"query":"GitLab"}"#)),
            .finished(.toolCalls),
        ])
        model.enqueueEventStream([
            .toolCall(call("activate_skill", arguments: #"{"skill_id":"mcp__gitlab"}"#)),
            .finished(.toolCalls),
        ])
        let toolCalls = ([allowed] + excluded).map { call($0) }
        model.enqueueEventStream(toolCalls.map { .toolCall($0) } + [.finished(.toolCalls)])
        model.enqueueEventStream([.contentDelta("Checked current issues."), .finished(.stop)])
        let (produced, _) = await BackgroundPromptService.runChatLoop(
            apiMessages: [ChatMessage(role: "user", content: "Check GitLab")], registry: registry,
            agent: agent, provider: provider, chatService: model, signalBox: signals,
            skillSession: state, accessPolicy: access, permissionPolicy: policy
        )
        let advertised = Set((model.capturedEventTools ?? []).map(\.function.name))
        #expect(advertised.contains(allowed))
        #expect(excluded.allSatisfy { !advertised.contains($0) })
        #expect(InitiativeMCPProtocol.calledTools == ["list_issues"])
        #expect(produced.contains { $0.content?.contains("Current issue #324") == true })
        for toolCall in toolCalls.dropFirst() {
            #expect(produced
                .contains {
                    $0.toolCallID == toolCall.id && $0.content?.contains("Unknown tool") == true
                })
        }
        #expect(chat.activeSkillEntries.isEmpty)
        #expect(manager.isConnected(serverID: server.id))
        #expect(server.cachedToolNames.contains("new_tool"))
    }

    @Test func chatLoopUsesSharedActivationAndPersistsToolCallLinkage() async throws {
        let (container, agent, chat) = try fixture()
        let provider = Provider(name: "Test", baseURL: "https://model.test")
        container.mainContext.insert(provider)
        agent.providerID = provider.id
        agent.bootstrapComplete = true
        chat.title = "Skills"
        chat.titleOrigin = .edited
        let server = MCPServer(name: "GitLab", url: "https://gitlab.test/mcp", authType: .oauth)
        container.mainContext.insert(server)
        let allowed = "mcp__gitlab__list_issues"
        container.mainContext.insert(AgentToolGrant(
            agentID: agent.id, kind: .discovered, key: allowed, level: .always
        ))
        InitiativeMCPProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [InitiativeMCPProtocol.self]
        let manager = MCPServerManager(
            keychainService: PreviewKeychainService(), oauthService: StoredBackgroundMCPAuth(),
            httpConfiguration: configuration
        )
        Container.shared.mcpServerManager.register { manager }
        let model = FakeChatService()
        Container.shared.chatService.register { model }
        let activation = call("activate_skill", arguments: #"{"skill_id":"mcp__gitlab"}"#)
        model.enqueueEventStream([.toolCall(activation), .finished(.toolCalls)])
        model.enqueueEventStream([.toolCall(call(allowed)), .finished(.toolCalls)])
        model.enqueueEventStream([.contentDelta("Checked GitLab."), .finished(.stop)])
        let vm = ChatViewModel(chatID: chat.id)
        vm.setUp(modelContext: container.mainContext)
        vm.chat = chat
        vm.gatekeeper = Gatekeeper(
            proactivity: agent.proactivity,
            knowledgeService: PreviewKnowledgeService()
        )
        vm.messageText = "Check GitLab"
        vm.send(agent: agent, provider: provider, space: nil, spaces: [], mcpServers: [server])
        await vm.streamTask?.value
        #expect(vm.chatError == nil)
        #expect(InitiativeMCPProtocol.calledTools == ["list_issues"])
        #expect(model.capturedEventTools?.contains { $0.function.name == allowed } == true)
        #expect(vm.window.messages.contains { $0.content?.contains("Current issue #324") == true })
        let entry = try #require(chat.activeSkillEntries.first { $0.skillID == "mcp__gitlab" })
        #expect(entry.activatingToolCallID == activation.id)
        let result = try #require(vm.window.messages.first { $0.toolCallID == activation.id }?
            .content)
        let payload = try #require(JSONSerialization
            .jsonObject(with: Data(result.utf8)) as? [String: Any])
        let activated = try #require(payload["result"] as? [String: Any])
        let reported = try #require(activated["tools_available"] as? [String])
        let advertised = Set((model.capturedEventTools ?? []).map(\.function.name))
        #expect(Set(reported).isSubset(of: advertised))
        #expect(reported.contains(allowed))
    }

    @Test func smallContextPreparationDoesNotConnectPersistedMCPSkills() async throws {
        let (container, agent, chat) = try fixture()
        let server = MCPServer(name: "GitLab", url: "https://gitlab.test/mcp", authType: .oauth)
        container.mainContext.insert(server)
        SkillActivation.activate(skillID: "mcp__gitlab", on: chat, activatingToolCallID: "previous")
        let manager = MCPServerManager(
            keychainService: PreviewKeychainService(),
            oauthService: BackgroundMCPAuth()
        )
        Container.shared.mcpServerManager.register { manager }
        let state = SkillSession(
            chatID: chat.id, permissionPolicy: AlwaysAllowPolicy(),
            accessPolicy: SpaceAccessPolicy(currentSpaceID: nil, publicSpaceIDs: []),
            agentID: agent.id, isSmallContext: true
        )
        await state.prepareActiveSkills(agent: agent)
        #expect(!manager.isConnected(serverID: server.id))
        #expect(manager.connectionErrors.isEmpty)
        #expect(state.tools().isEmpty)
    }

    @Test func maintenanceActivationStillRequiresChat() async throws {
        let (container, agent, _) = try fixture()
        defer { _ = container }
        let registry = ToolRegistry.background(onSignal: { _ in })
        let result = await registry.execute(
            call("activate_skill", arguments: #"{"skill_id":"web"}"#),
            agent: agent
        )
        #expect(result.isError)
        #expect(result.content.contains("No chat context"))
    }
}

private struct BackgroundMCPAuth: MCPOAuthService {
    func discoverOAuth(for serverURL: URL) async throws -> OAuthConfiguration? {
        Issue.record("Background activation must not discover authorization")
        return nil
    }

    func authorize(config: OAuthConfiguration, serverID: UUID) async throws -> String {
        Issue.record("Background activation must not authorize")
        throw MCPServerConnection.ConnectionError.authExpired
    }

    func validToken(for serverID: UUID) async throws -> String? {
        throw MCPServerConnection.ConnectionError.authExpired
    }

    func clearTokens(for serverID: UUID) {}
}
