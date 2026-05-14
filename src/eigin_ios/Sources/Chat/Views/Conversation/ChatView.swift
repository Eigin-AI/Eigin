import Factory
import SwiftData
import SwiftUI

/// The active chat screen: message feed, input bar, streaming, and live call access.
struct ChatView: View {
    let chatID: UUID

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colors) private var colors
    @Injected(\.voiceService) private var voiceService
    @Injected(\.speechService) private var speechService
    @Injected(\.dictationService) private var dictationService
    @Environment(\.scenePhase) private var scenePhase
    @Injected(\.languageManager) private var languageManager
    @Query(sort: \Provider.createdAt) private var providers: [Provider]
    @Query(filter: #Predicate<Agent> { $0.bootstrapComplete })
    private var agents: [Agent]
    @Query private var spaces: [Space]
    @Query(filter: #Predicate<MCPServer> { $0.isEnabled }) private var mcpServers: [MCPServer]

    @State private var viewModel: ChatViewModel
    @State private var showLiveCall = false
    @State private var voiceDownloadItem: AssetItem?
    @State private var isEditingTitle = false
    @State private var editingTitleText = ""
    @FocusState private var isTitleFocused: Bool

    init(chatID: UUID) {
        self.chatID = chatID
        _viewModel = State(initialValue: ChatViewModel(chatID: chatID))
    }

    private var agent: Agent? {
        guard let chat = viewModel.chat else { return nil }
        return agents.first { $0.id == chat.agentID }
    }

    private var activeProvider: Provider? {
        guard let agent else { return nil }
        return providers.first { $0.id == agent.providerID }
    }

    private var space: Space? {
        guard let spaceID = viewModel.chat?.spaceID else { return nil }
        return spaces.first { $0.id == spaceID }
    }

    private var agentSpaceSnapshots: [SpaceSnapshot] {
        guard let agent else { return [] }
        return spaces
            .filter { $0.agentID == agent.id && $0.bootstrapComplete }
            .map { SpaceSnapshot(
                id: $0.id,
                name: $0.name,
                emoji: $0.emoji,
                instructions: $0.instructions
            ) }
    }

    private var canSend: Bool {
        agent != nil && activeProvider != nil
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        VStack(spacing: 0) {
            if !canSend, viewModel.window.messages.isEmpty {
                ContentUnavailableView(
                    "No Agent",
                    systemImage: "person.crop.circle",
                    description: Text(Localized.Agent.EmptyState.setupHint)
                )
            } else {
                ChatFeed(
                    items: viewModel.chatItems,
                    throttler: viewModel.chatLoop.throttler,
                    splitter: viewModel.chatLoop.splitter,
                    messageText: $viewModel.messageText,
                    isInputDisabled: !canSend || viewModel.isStreaming || viewModel.isCompacting,
                    onSend: { context in
                        guard let agent, let provider = activeProvider else { return }
                        viewModel.send(
                            context: context,
                            agent: agent,
                            provider: provider,
                            space: space,
                            spaces: spaces,
                            mcpServers: mcpServers
                        )
                    },
                    onStop: viewModel.isStreaming ? { viewModel.handleStop() } : nil,
                    pagination: FeedPagination(
                        hasOlderMessages: viewModel.window.hasOlderMessages,
                        onLoadMore: { viewModel.window.loadOlderMessages() },
                        hasNewerMessages: viewModel.window.hasNewerMessages,
                        onLoadNewer: { viewModel.window.loadNewerMessages() },
                        onSnapToBottom: { viewModel.window.snapToBottom() },
                        onScrollPositionChanged: { isAtBottom in
                            viewModel.window.isUserAtBottom = isAtBottom
                        }
                    ),
                    interactions: FeedInteractions(
                        permissionRequest: viewModel.chatLoop.pendingPermission,
                        onPermissionResponse: { response in
                            viewModel.chatLoop.resolvePermission(response)
                        },
                        browsingRequest: viewModel.chatLoop.pendingBrowsing,
                        onBrowsingComplete: { result in viewModel.chatLoop.resolveBrowsing(result) }
                    ),
                    context: FeedContext(
                        agentName: agent?.name ?? "",
                        spaces: agentSpaceSnapshots,
                        currentSpaceID: viewModel.chat?.spaceID,
                        onMoveToSpace: { spaceID in viewModel.moveToSpace(spaceID) }
                    ),
                    lastStreamedItemID: viewModel.lastStreamedItemID
                )
            }
        }
        .background(colors.surface.standard.base.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                titleView
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    if let asset = voiceService.upgradeAsset(for: languageManager.currentLanguage),
                       !asset.state.isDownloading
                    {
                        voiceDownloadItem = AssetItem(asset)
                    } else {
                        showLiveCall = true
                    }
                } label: {
                    Image(systemName: "phone.fill")
                }
                .disabled(!canSend || viewModel.isStreaming || viewModel.isCompacting)
            }
        }
        .fullScreenCover(isPresented: $showLiveCall) {
            if let agent, let provider = activeProvider {
                LiveCallView(
                    agent: agent,
                    provider: provider,
                    initialMessages: viewModel.window.isPreloaded
                        ? viewModel.window.allPersisted.map { $0.toChatMessage() }
                        : viewModel.window.messages,
                    messages: $viewModel.window.messages,
                    isPresented: $showLiveCall,
                    permissionPolicy: viewModel.loadPermissionPolicy(for: agent),
                    chatID: viewModel.chat?.id,
                    spaceID: viewModel.chat?.spaceID,
                    space: space,
                    mcpServers: mcpServers,
                    onPersist: { [modelContext] newMessages in
                        guard let chat = viewModel.chat else { return }
                        for cm in newMessages {
                            let message = Message.from(cm)
                            message.chat = chat
                            modelContext.insert(message)
                        }
                        chat.updatedAt = .now
                    },
                    onChatGrant: { [modelContext] capabilities in
                        guard let chat = viewModel.chat else { return }
                        for capability in capabilities {
                            let grant = ChatToolGrant(chatID: chat.id, capability: capability)
                            modelContext.insert(grant)
                        }
                    }
                )
            }
        }
        .sheet(item: $voiceDownloadItem) { item in
            AssetDownloadPrompt(
                asset: item.asset,
                onAccept: {
                    voiceDownloadItem = nil
                    showLiveCall = true
                },
                onDecline: {
                    voiceDownloadItem = nil
                    showLiveCall = true
                }
            )
            .presentationDetents([.medium])
        }
        .sheet(isPresented: Binding(
            get: { viewModel.pendingEmailCompose != nil },
            set: { if !$0 { viewModel.pendingEmailCompose = nil } }
        )) {
            if let (request, continuation) = viewModel.pendingEmailCompose {
                MailComposeView(request: request, continuation: continuation)
                    .ignoresSafeArea()
            }
        }
        .onAppear {
            viewModel.setUp(modelContext: modelContext)
            viewModel.loadChat(agents: agents)
            syncVoice()
        }
        .onChange(of: agent?.voiceIdentifier) { syncVoice() }
        .onDisappear {
            viewModel.cleanupEmptyChatIfNeeded()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background, viewModel.isStreaming {
                viewModel.beginBackgroundGrace()
            }
            if newPhase == .active {
                viewModel.endBackgroundGrace()
            }
            if newPhase == .active, !viewModel.window.messages.isEmpty {
                if let agent, let provider = activeProvider {
                    viewModel.generateTitle(agent: agent, provider: provider)
                }
            }
        }
        .onChange(of: showLiveCall) { wasPresented, isPresented in
            if wasPresented, !isPresented {
                viewModel.syncLiveCallMessages()
                if let agent, let provider = activeProvider {
                    viewModel.generateTitle(agent: agent, provider: provider)
                }
            }
        }
    }

    // MARK: - Title Editing

    private var titleView: some View {
        VStack(spacing: 2) {
            if isEditingTitle {
                TextField("Chat name", text: $editingTitleText)
                    .typography(Typography.titleXS)
                    .multilineTextAlignment(.center)
                    .focused($isTitleFocused)
                    .onSubmit { commitTitleEdit() }
                    .onChange(of: isTitleFocused) { _, focused in
                        if !focused { commitTitleEdit() }
                    }
                    .onAppear {
                        editingTitleText = viewModel.chat?.title ?? ""
                        isTitleFocused = true
                    }
            } else {
                Text(viewModel.chat?.title.isEmpty == false ? viewModel.chat!.title : Localized
                    .Tools.New.chat)
                    .typography(Typography.titleXS)
                    .foregroundStyle(colors.text.standard.base)
                    .onTapGesture {
                        editingTitleText = viewModel.chat?.title ?? ""
                        withAnimation(Animations.snap) {
                            isEditingTitle = true
                        }
                    }
            }
        }
    }

    private func syncVoice() {
        var service = speechService
        service.voiceIdentifier = agent?.voiceIdentifier
    }

    private func commitTitleEdit() {
        let trimmed = editingTitleText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            viewModel.chat?.title = trimmed
            viewModel.chat?.titleOrigin = .edited
            viewModel.chat?.updatedAt = .now
            Haptics.light()
        }
        withAnimation(Animations.snap) {
            isEditingTitle = false
        }
    }
}
