import Factory
import Foundation
import SwiftData
import SwiftUI

/// Orchestrates chat state: messaging, streaming, pagination, compaction, and persistence.
@Observable @MainActor
final class ChatViewModel {
    // MARK: - Configuration

    let chatID: UUID

    // MARK: - Dependencies

    private var modelContext: ModelContext!
    private var voiceService: any VoiceService {
        Container.shared.voiceService()
    }

    private var dictationService: any DictationService {
        Container.shared.dictationService()
    }

    private var languageManager: LanguageManager {
        Container.shared.languageManager()
    }

    private var attachmentStore: any ChatAttachmentStoring {
        Container.shared.chatAttachmentStore()
    }

    // MARK: - State

    var chat: Chat?
    var messageText = ""
    var window = MessageWindow()
    var chatLoop = AgenticChatLoop(isBootstrap: false)
    var streamTask: Task<Void, Never>?
    private(set) var chatError: ConnectionError?
    var isCompacting = false
    /// True from the moment a turn is kicked off (user send or retry) until the
    /// stream task completes. Covers the gap before the throttler enters
    /// `.waiting`, during which `isStreaming` is still false — used to hide the
    /// retry footer and guard against duplicate retriggers.
    private(set) var isTurnInProgress = false
    var compactionProgress = ChasingProgress()
    var gatekeeper: Gatekeeper?
    private var backgroundGuard: BackgroundTaskGuard?

    /// Images staged in the composer, waiting to be attached to the next sent message.
    var stagedAttachments: [MessageAttachment] = []

    /// Maximum number of images a single message can carry. Keeps request
    /// payloads bounded and avoids cluttering the chat feed with a large gallery.
    static let maxStagedAttachments = 4

    private var didLoad = false

    // MARK: - Computed

    var isStreaming: Bool {
        chatLoop.phase == .waiting || chatLoop.phase == .streaming
    }

    var chatItems: [ChatItem] {
        var items = ChatItem.buildItems(
            from: window.messages + chatLoop.committedMessages,
            chatLoop: chatLoop,
            chatError: chatError
        )
        if isCompacting, !compactionProgress.isFinished {
            items.append(
                .compaction(id: "compacting", progress: compactionProgress.value, summary: nil)
            )
        }
        return items
    }

    // MARK: - Staged attachments

    /// Stages `attachment` for the next sent message if under
    /// ``maxStagedAttachments``. Returns whether it was staged.
    @discardableResult
    func stageAttachment(_ attachment: MessageAttachment) -> Bool {
        guard stagedAttachments.count < Self.maxStagedAttachments else { return false }
        stagedAttachments.append(attachment)
        return true
    }

    // MARK: - Init

    init(chatID: UUID) {
        self.chatID = chatID
    }

    // MARK: - Setup

    func setUp(modelContext: ModelContext) {
        guard self.modelContext == nil else { return }
        self.modelContext = modelContext
    }

    // MARK: - Loading

    func loadChat(agents: [Agent]) {
        guard !didLoad else { return }
        didLoad = true

        let id = chatID
        let chatDescriptor = FetchDescriptor<Chat>(
            predicate: #Predicate<Chat> { $0.id == id }
        )
        guard let fetched = try? modelContext.fetch(chatDescriptor).first else {
            return
        }
        chat = fetched

        if let agent = agents.primary {
            gatekeeper = Gatekeeper(
                proactivity: agent.proactivity,
                knowledgeService: Container.shared.knowledgeService()
            )
        }

        preloadAllMessages()
    }

    func preloadAllMessages() {
        let id = chatID
        Task {
            let descriptor = FetchDescriptor<Message>(
                predicate: #Predicate<Message> { $0.chat?.id == id },
                sortBy: [SortDescriptor(\.timestamp)]
            )
            window.allPersisted = (try? modelContext.fetch(descriptor)) ?? []
            window.isPreloaded = true
            window.messages = window.loadInitialWindow()
        }
    }

    func refreshAllPersisted() {
        let id = chatID
        let descriptor = FetchDescriptor<Message>(
            predicate: #Predicate<Message> { $0.chat?.id == id },
            sortBy: [SortDescriptor(\.timestamp)]
        )
        window.allPersisted = (try? modelContext.fetch(descriptor)) ?? []
        // Keep windowStartIndex consistent
        window.windowStartIndex = max(
            0, min(window.windowStartIndex, window.allPersisted.count - window.messages.count)
        )
        window.isPreloaded = true
    }

    // MARK: - Streaming

    func send(
        context: InteractionMode = .text,
        agent: Agent,
        provider: Provider,
        space: Space?,
        spaces: [Space],
        mcpServers: [MCPServer],
        integrations: [Integration] = []
    ) {
        let text = messageText.trimmingCharacters(in: .whitespaces)
        let pendingAttachments = stagedAttachments
        guard !text.isEmpty || !pendingAttachments.isEmpty else { return }

        // If an interactive tool is waiting (e.g. options are showing), stop the current
        // turn cleanly before starting the new user-message turn. handleStop() cancels
        // the pending options continuation via stop(), so no double-resume.
        if chatLoop.isAwaitingUserInteraction {
            handleStop()
        }

        // Snap window to bottom if scrolled away
        if window.hasNewerMessages { window.snapToBottom() }

        let userMessage = ChatMessage(
            role: "user",
            content: text.isEmpty ? nil : text,
            attachments: pendingAttachments.isEmpty ? nil : pendingAttachments
        )
        window.messages.append(userMessage)
        if !text.isEmpty { seedTitle(from: text) }
        messageText = ""
        stagedAttachments = []
        chatError = nil

        let hasSpaces = spaces.contains(where: { $0.agentID == agent.id })
        let needsCompaction = chat?.needsCompaction ?? false

        let policy = loadPermissionPolicy(for: agent)
        let chatID = chat?.id ?? UUID()

        wirePermissionCallbacks(policy: policy, chatID: chatID)

        let servers = mcpServers

        guard let gatekeeper else {
            AppLogger.warning(
                "ChatViewModel.send called before gatekeeper was constructed", category: .chat
            )
            return
        }

        isTurnInProgress = true
        streamTask = Task {
            defer {
                self.endBackgroundGrace()
                self.isTurnInProgress = false
            }
            let msgs =
                self.window.isPreloaded
                    ? self.window.allPersisted.map { $0.toChatMessage() } + [userMessage]
                    : self.window.messages
            // Route before the turn is built: the prompt budget and tool registry are
            // sized from the model that ends up running.
            let (provider, routedModel) = await self.applyRoute(
                agent: agent, provider: provider, messages: msgs
            )

            let activeSkills = self.resolvedActiveSkills(
                integrations: integrations,
                mcpServers: servers
            )

            let turn = await MessagePipeline.prepareTurn(
                messages: msgs,
                agent: agent, model: routedModel, space: space,
                permissionPolicy: policy,
                spaceID: chat?.spaceID, chatID: chat?.id,
                mcpServers: servers,
                integrations: integrations,
                activeSkills: activeSkills,
                activeFlow: chat?.activeFlow,
                gatekeeper: gatekeeper,
                mode: context,
                hasSpaces: hasSpaces,
                needsCompaction: needsCompaction,
                onBrowse: { [weak self] browsingRequest in
                    guard let self else { return .cancelled }
                    return await chatLoop.requestBrowsing(browsingRequest)
                },
                onPresentOptions: { [weak self] optionSet in
                    guard let self else { return .dismissed }
                    return await chatLoop.presentOptions(optionSet)
                }
            )

            let apiMessages = await applyCompactionIfNeeded(
                turn: turn, provider: provider, model: routedModel, agent: agent
            )

            persistMessage(userMessage)
            let registry = turn.registry

            // Rebuild tool registry mid-turn when skills are activated.
            let browseHandler: BrowseHandler? = { [weak self] browsingRequest in
                guard let self else { return .cancelled }
                return await chatLoop.requestBrowsing(browsingRequest)
            }
            let optionsHandler: OptionsHandler? = { [weak self] optionSet in
                guard let self else { return .dismissed }
                return await chatLoop.presentOptions(optionSet)
            }
            self.chatLoop.onToolsChanged = { [weak self] in
                guard let self else { return (tools: registry.definitions, executor: registry) }
                let updatedSkills = resolvedActiveSkills(
                    integrations: integrations,
                    mcpServers: servers
                )

                let contextWindow = KnownModelCatalog.lookup(routedModel)?.contextWindow ?? 128_000
                let isSmallContext = contextWindow <= MessagePipeline.smallContextThreshold

                let activeOnDemand = updatedSkills.last
                let updatedRegistry: ToolRegistry
                if isSmallContext {
                    updatedRegistry = ToolRegistry.smallChat(
                        chatID: chat?.id,
                        agentID: agent.id,
                        permissionPolicy: policy,
                        activeSkill: activeOnDemand
                    )
                } else {
                    // Connect only the MCP servers backing active skills (e.g. one
                    // just activated by this round's tool call) and gather fresh
                    // tool proxies — turn.mcpTools reflects only what was active
                    // at turn start.
                    let activeMCPSkillIDs = Set(updatedSkills.map(\.id))
                        .intersection(turn.mcpSkills.map(\.id))
                    nonisolated(unsafe) let activeMCPServers = activeMCPSkillIDs.compactMap {
                        MCPServerSkill.server(forSkillID: $0, servers: servers)
                    }
                    let mcpTools = await Container.shared.mcpServerManager()
                        .prepareTools(servers: activeMCPServers)
                    updatedRegistry = ToolRegistry.chat(
                        spaceID: chat?.spaceID, chatID: chat?.id,
                        agentID: agent.id,
                        permissionPolicy: policy,
                        activeSkills: BundledSkill.alwaysActive
                            + updatedSkills.filter { !$0.alwaysActive },
                        mcpTools: mcpTools,
                        mcpSkills: turn.mcpSkills,
                        integrationToolsByCapability: turn.integrationToolsByCapability,
                        onBrowse: browseHandler,
                        onPresentOptions: optionsHandler
                    )
                }
                return (tools: updatedRegistry.definitions, executor: updatedRegistry)
            }

            do {
                _ = try await chatLoop.run(
                    messages: apiMessages,
                    tools: registry.definitions,
                    agent: agent,
                    provider: provider,
                    chatService: Container.shared.chatService(),
                    toolExecutor: registry,
                    cacheKey: chatID.uuidString,
                    model: routedModel,
                    initialToolCalls: turn.initialToolCalls
                )
                let completed = chatLoop.completeRound()
                window.messages.append(contentsOf: completed)
                window.trimIfNeeded()
                persistMessages(completed)

                let assistantCount = window.messages.count(where: { $0.role == "assistant" })
                if assistantCount >= ChatTitleGenerator.titleGenerationThreshold {
                    generateTitle(agent: agent, provider: provider, model: routedModel)
                }
            } catch {
                // A user-initiated stop cancels streamTask, which surfaces here as a
                // cancellation error (Swift's CancellationError or URLSession's -999).
                // That's not a failure — handleStop already snapshotted the partial
                // response, so settle quietly without painting an error banner.
                if !(Task.isCancelled || error is CancellationError) {
                    chatError = ConnectionError(from: error)
                }
                chatLoop.abort()
            }
        }
    }

    /// Asks the router where this turn should run and applies the answer.
    ///
    /// A route that stays on the user's provider is written back to the agent, so the
    /// choice survives relaunch and keeps the provider's prompt cache warm. An offline
    /// detour is not: `providerID` and `model` keep pointing at what the user picked, and
    /// the next online turn returns there on its own.
    private func applyRoute(
        agent: Agent, provider: Provider, messages: [ChatMessage]
    ) async -> (provider: Provider, model: String) {
        guard let request = RouteRequest(agent: agent, provider: provider, messages: messages)
        else {
            return (provider, agent.model)
        }
        let route = await Container.shared.modelRouter().resolve(request)

        guard !route.staysOn(providerID: provider.id) else {
            agent.model = route.model
            return (provider, route.model)
        }
        let routedID = route.providerID
        guard let context = agent.modelContext,
              let routed = try? context.fetch(
                  FetchDescriptor<Provider>(predicate: #Predicate { $0.id == routedID })
              ).first
        else {
            return (provider, agent.model)
        }
        return (routed, route.model)
    }

    func handleStop() {
        endBackgroundGrace()
        let checkpoint = chatLoop.stop()
        window.messages.append(contentsOf: checkpoint)
        chatLoop.settle()
        window.trimIfNeeded()
        chatError = nil
        streamTask?.cancel()
        persistMessages(checkpoint)
    }

    /// Re-runs the trailing user message as a fresh turn.
    ///
    /// Rewinds: removes the last user message from the in-memory window, the
    /// persisted cache, and SwiftData, then delegates to `send` with the text
    /// restored to `messageText`. `send` re-appends and re-persists the message
    /// exactly as if the user had typed it fresh — the turn pipeline runs
    /// unmodified.
    ///
    /// No-op unless the last message is a user message with non-empty content
    /// and no turn is in progress. If `handleStop` left a partial assistant
    /// reply as the last message, that message is last — not the user message —
    /// so this bails out and the footer is hidden (the user sends a new message
    /// instead).
    func retryLastTurn(
        agent: Agent,
        provider: Provider,
        space: Space?,
        spaces: [Space],
        mcpServers: [MCPServer],
        integrations: [Integration] = []
    ) {
        guard !isTurnInProgress,
              let chat,
              let last = window.messages.last,
              last.role == "user",
              let content = last.content?.trimmingCharacters(in: .whitespaces),
              !content.isEmpty
        else { return }

        if chatLoop.isAwaitingUserInteraction { handleStop() }

        // Ask the window to rewind the trailing user message; `send` re-appends and
        // re-persists it exactly as if typed fresh. The window owns the counting
        // invariant; here we only clean up the persisted row it hands back.
        guard let rewound = window.rewindTrailingUserMessage() else { return }
        if let persisted = rewound.persisted {
            if let attachments = persisted.attachments {
                attachmentStore.deleteAll(attachments)
            }
            modelContext.delete(persisted)
        }
        chat.updatedAt = .now

        if window.hasNewerMessages { window.snapToBottom() }
        chatError = nil

        messageText = content
        send(
            agent: agent,
            provider: provider,
            space: space,
            spaces: spaces,
            mcpServers: mcpServers,
            integrations: integrations
        )
    }

    // MARK: - Background Grace

    func beginBackgroundGrace() {
        guard isStreaming, backgroundGuard == nil else { return }
        backgroundGuard = BackgroundTaskGuard { [weak self] in
            self?.handleStop()
        }
        backgroundGuard?.begin()
    }

    func endBackgroundGrace() {
        backgroundGuard?.end()
        backgroundGuard = nil
    }

    // MARK: - Compaction

    /// `model` is the routed model, which on an offline turn is not `agent.model`. It
    /// decides the output reservation, so a mismatch here silently starves the input
    /// budget rather than failing.
    private func applyCompactionIfNeeded(
        turn: MessagePipeline.TurnInputs,
        provider: Provider,
        model: String,
        agent: Agent
    ) async -> [ChatMessage] {
        let onProgress: @Sendable (CompactionPhase) -> Void = { [weak self] phase in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if !self.isCompacting {
                        self.isCompacting = true
                        self.compactionProgress.reset()
                        self.chat?.needsCompaction = true
                    }
                    switch phase {
                    case .waiting:
                        self.compactionProgress.setTarget(0.25)
                    case .streaming(let p):
                        self.compactionProgress.setTarget(0.25 + p * 0.50)
                    case .finalizing:
                        self.compactionProgress.setTarget(1.0)
                    }
                }
            }
        }

        let result = await MessagePipeline.compactIfNeeded(
            apiMessages: turn.apiMessages,
            estimatedTokens: turn.estimatedTokens,
            contextWindow: turn.contextWindow,
            needsCompaction: chat?.needsCompaction ?? false,
            baseURL: provider.baseURL,
            providerID: provider.id,
            model: model,
            chatService: Container.shared.chatService(),
            onProgress: onProgress
        )

        chat?.needsCompaction = result.needsCompaction

        guard let summaryMessage = result.summary else {
            if isCompacting {
                compactionProgress.reset()
                isCompacting = false
            }
            return result.apiMessages
        }

        persistMessage(summaryMessage)
        chat?.clearActiveSkills()
        refreshAllPersisted()
        try? modelContext.save()

        while !compactionProgress.isFinished {
            try? await Task.sleep(for: .milliseconds(50))
        }

        window.messages.append(summaryMessage)

        compactionProgress.reset()
        isCompacting = false

        return result.apiMessages
    }

    // MARK: - Persistence

    func persistMessage(_ chatMessage: ChatMessage) {
        guard let chat else { return }
        let message = Message.from(chatMessage)
        message.chat = chat
        modelContext.insert(message)
        chat.updatedAt = .now
        if window.isPreloaded { window.allPersisted.append(message) }
    }

    func persistMessages(_ chatMessages: [ChatMessage]) {
        guard let chat, !chatMessages.isEmpty else { return }
        for cm in chatMessages {
            let message = Message.from(cm)
            message.chat = chat
            modelContext.insert(message)
            if window.isPreloaded { window.allPersisted.append(message) }
        }
        chat.updatedAt = .now
    }

    func syncLiveCallMessages() {
        refreshAllPersisted()
        window.messages = window.loadInitialWindow()
    }

    /// Surfaces an error from an abnormally-ended live call as a chat error card,
    /// matching how a failed send is displayed.
    func setLiveCallError(_ error: Error) {
        chatError = ConnectionError(from: error)
    }

    // MARK: - Title Generation

    func generateTitle(
        agent: Agent,
        provider: Provider,
        model: String? = nil,
        using overrideMessages: [ChatMessage]? = nil
    ) {
        guard let chat else { return }
        ChatTitleGenerator.generate(
            chat: chat, messages: window.messages,
            agent: agent, provider: provider, model: model,
            chatService: Container.shared.chatService(),
            using: overrideMessages
        )
    }

    func seedTitle(from content: String) {
        guard let chat else { return }
        ChatTitleGenerator.seed(chat: chat, from: content)
    }

    // MARK: - Permissions

    /// The chat's persisted active skills, dropping any whose required
    /// capability is no longer connected — e.g. the user activated `email`
    /// then disconnected their Google account. Without this, a stale skill
    /// would keep injecting instructions ("if an email account is
    /// connected...") and the agent could still try to call its tools, which
    /// ``IntegrationManager`` no longer supplies, landing on "Unknown tool".
    private func resolvedActiveSkills(
        integrations: [Integration],
        mcpServers: [MCPServer]
    ) -> [Skill] {
        let connected = Container.shared.integrationManager()
            .connectedCapabilities(integrations: integrations)
        return (chat?.activeSkillEntries ?? [])
            .compactMap { SkillCatalog.skill(forID: $0.skillID, mcpServers: mcpServers) }
            .filter { skill in
                skill.requiredCapabilities.isEmpty
                    || !skill.requiredCapabilities.isDisjoint(with: connected)
            }
    }

    func loadPermissionPolicy(for agent: Agent) -> AgentPermissionPolicy {
        PermissionPolicyLoader.load(
            for: agent,
            chatID: chat?.id,
            modelContext: modelContext
        )
    }

    private func wirePermissionCallbacks(policy: AgentPermissionPolicy, chatID: UUID) {
        chatLoop.permissionPolicy = policy
        let context = modelContext!
        chatLoop.onChatGrant = { capabilities in
            for capability in capabilities {
                let grant = ChatToolGrant(chatID: chatID, capability: capability)
                context.insert(grant)
            }
        }
    }

    // MARK: - Helpers

    func moveToSpace(_ spaceID: UUID?) {
        if let chat {
            ChatMigration.moveChat(chat, toSpaceID: spaceID, context: modelContext)
        }
        Haptics.medium()
    }
}
