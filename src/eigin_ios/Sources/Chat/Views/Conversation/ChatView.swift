import Factory
import SwiftData
import SwiftUI
import UIKit

/// The active chat screen: message feed, input bar, streaming, and live call access.
struct ChatView: View {
    let chatID: UUID
    /// What the chat should arm on open, or `nil` for a plain open.
    var opening: ChatOpening?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colors) private var colors
    @Injected(\.voiceService) private var voiceService
    @Injected(\.speechService) private var speechService
    @Injected(\.dictationService) private var dictationService
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.markdownRenderConfig) private var markdownRenderConfig
    @Injected(\.markdownDocumentCache) private var markdownDocumentCache
    @Injected(\.languageManager) private var languageManager
    @Query(sort: \Provider.createdAt) private var providers: [Provider]
    @Query private var agents: [Agent]
    @Query private var spaces: [Space]
    @Query(filter: #Predicate<MCPServer> { $0.isEnabled }) private var mcpServers: [MCPServer]
    @Query(filter: #Predicate<Integration> { $0.isEnabled }) private var integrations: [Integration]

    @State private var viewModel: ChatViewModel
    @State private var showLiveCall = false
    @State private var voiceDownloadItem: AssetItem?
    @State private var didPresentStartLiveCall = false
    @State private var showNonVisionStagedWarning = false
    @State private var supportsVision = false
    /// False until the loaded history has been parsed into ``MarkdownDocumentCache``, so
    /// the feed's first frame draws at final heights instead of settling into them.
    @State private var isContentReady = false
    @Environment(\.dismiss) private var dismiss
    @Injected(\.chatAttachmentStore) private var attachmentStore

    init(chatID: UUID, opening: ChatOpening? = nil) {
        self.chatID = chatID
        self.opening = opening
        _viewModel = State(initialValue: ChatViewModel(chatID: chatID))
    }

    private var agent: Agent? {
        guard viewModel.chat != nil else { return nil }
        return agents.primary
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

    /// Under automatic selection there is no model yet when composing, so the question is
    /// whether the router *could* find one that sees, not whether the current one does.
    private func refreshVisionSupport() async {
        guard let agent, let provider = activeProvider,
              let request = RouteRequest(
                  agent: agent,
                  provider: provider,
                  requirements: RouteRequirements(needsVision: true)
              )
        else {
            supportsVision = false
            return
        }
        supportsVision = await Container.shared.modelRouter().canSatisfy(request)
    }

    /// Prewarms the loaded history's markdown before the feed is revealed. Only assistant
    /// messages, and only the blocks the library draws: code, dividers and tables have
    /// their own views.
    private func prewarmMarkdown() async {
        guard viewModel.window.isPreloaded, !isContentReady else { return }
        // Documents are cached by block text, so the message ID here is immaterial.
        let texts = viewModel.window.messages
            .filter { $0.role != "user" }
            .compactMap(\.content)
            .flatMap { ContentBlock.split($0, messageID: "", isStreaming: false) }
            .filter { $0.kind.usesMarkdownRenderer }
            .map(\.text)
        await markdownDocumentCache.prewarm(texts, config: markdownRenderConfig)
        withAnimation(.easeIn(duration: Animations.fast)) { isContentReady = true }
    }

    /// Changes that could alter which models are on offer.
    private var visionGateKey: String {
        "\(agent?.model ?? "")|\(agent?.autoModel ?? false)|\(activeProvider?.id.uuidString ?? "")|\(activeProvider?.availableModels.count ?? 0)"
    }

    private var showVoiceDownload: Binding<Bool> {
        Binding(
            get: { voiceDownloadItem != nil },
            set: { if !$0 { voiceDownloadItem = nil } }
        )
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        VStack(spacing: 0) {
            ChatHeaderView(
                chat: viewModel.chat,
                onBack: { dismiss() },
                onPhone: startLiveCall,
                isPhoneDisabled: !canSend || viewModel.isStreaming || viewModel.isCompacting
            )

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
                    streamingItemID: viewModel.chatLoop.streamingItemID,
                    messageText: $viewModel.messageText,
                    isInputDisabled: !canSend ||
                        (viewModel.isStreaming && !viewModel.chatLoop.isAwaitingUserInteraction) ||
                        viewModel.isCompacting,
                    autoStartDictation: opening == .dictation,
                    autoShowCamera: opening == .camera,
                    onSend: { context in
                        guard let agent, let provider = activeProvider else { return }
                        viewModel.send(
                            context: context,
                            agent: agent,
                            provider: provider,
                            space: space,
                            spaces: spaces,
                            mcpServers: mcpServers,
                            integrations: integrations
                        )
                    },
                    onStop: (viewModel.isStreaming && !viewModel.chatLoop
                        .isAwaitingUserInteraction) ? { viewModel.handleStop() } : nil,
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
                        onBrowsingComplete: { result in
                            viewModel.chatLoop.resolveBrowsing(result)
                        },
                        onOptionSelected: { label in
                            viewModel.chatLoop.resolveOptions(.selected(label: label))
                        },
                        onOptionDismissed: {
                            viewModel.chatLoop.resolveOptions(.dismissed)
                        }
                    ),
                    context: FeedContext(
                        agentName: agent?.name ?? "",
                        spaces: agentSpaceSnapshots,
                        currentSpaceID: viewModel.chat?.spaceID,
                        onMoveToSpace: { spaceID in viewModel.moveToSpace(spaceID) },
                        supportsVision: supportsVision,
                        stagedAttachments: viewModel.stagedAttachments,
                        onStageImage: stageImage,
                        onRemoveStagedAttachment: { attachment in
                            viewModel.stagedAttachments.removeAll { $0.id == attachment.id }
                            attachmentStore.delete(id: attachment.id)
                        }
                    ),
                    isLoaded: viewModel.window.isPreloaded,
                    isContentReady: isContentReady,
                    onUserMessageFooterAction: (!viewModel.isTurnInProgress && canSend)
                        ? {
                            guard let agent, let provider = activeProvider else { return }
                            viewModel.retryLastTurn(
                                agent: agent,
                                provider: provider,
                                space: space,
                                spaces: spaces,
                                mcpServers: mcpServers,
                                integrations: integrations
                            )
                        }
                        : nil
                )
            }
        }
        .background(colors.surface.standard.base.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
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
                    integrations: integrations,
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
                    },
                    onError: { error in
                        viewModel.setLiveCallError(error)
                    }
                )
            }
        }
        .appSheet(
            isPresented: showVoiceDownload,
            title: voiceDownloadItem?.asset.displayName ?? "",
            description: voiceDownloadItem?.asset.downloadDescription,
            detents: [.medium],
            fitsContent: true
        ) {
            AssetDownloadSheetContent(
                asset: voiceDownloadItem!.asset,
                onAccept: {
                    voiceDownloadItem = nil
                    showLiveCall = true
                },
                onDecline: {
                    voiceDownloadItem = nil
                    showLiveCall = true
                }
            )
        }
        .onAppear {
            viewModel.setUp(modelContext: modelContext)
            viewModel.loadChat(agents: agents)
            syncVoice()
            presentStartLiveCall()
        }
        .onChange(of: agent?.voiceIdentifier) { syncVoice() }
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
        .task(id: visionGateKey) { await refreshVisionSupport() }
        .task(id: viewModel.window.isPreloaded) { await prewarmMarkdown() }
        // Attempts are what change model health, so re-ask once each turn settles:
        // the last vision-capable model may have been quarantined mid-conversation.
        .onChange(of: viewModel.isTurnInProgress) { _, inProgress in
            guard !inProgress else { return }
            Task { await refreshVisionSupport() }
        }
        .onChange(of: showLiveCall) { wasPresented, isPresented in
            if wasPresented, !isPresented {
                viewModel.syncLiveCallMessages()
                if let agent, let provider = activeProvider {
                    viewModel.generateTitle(agent: agent, provider: provider)
                }
            }
        }
        .onChange(of: supportsVision) { _, nowSupports in
            // When the model switches away from vision, clear any staged images.
            if !nowSupports, !viewModel.stagedAttachments.isEmpty {
                attachmentStore.deleteAll(viewModel.stagedAttachments)
                viewModel.stagedAttachments = []
                showNonVisionStagedWarning = true
            }
        }
        .appSheet(
            isPresented: $showNonVisionStagedWarning,
            title: Localized.Attachment.imageStagedOnNonVisionTitle,
            description: Localized.Attachment.imageStagedOnNonVisionMessage,
            detents: [.medium],
            fitsContent: true
        ) {
            EmptyView()
        }
    }

    private func syncVoice() {
        var service = speechService
        service.voiceIdentifier = agent?.voiceIdentifier
    }

    /// Presents the live call a widget or shortcut launch asked for, once the
    /// chat is on screen. Reuses the phone button's voice-download gate.
    private func presentStartLiveCall() {
        guard opening == .liveCall, !didPresentStartLiveCall else { return }
        didPresentStartLiveCall = true
        startLiveCall()
    }

    /// Reuses the phone button's voice-download gate before presenting the live call.
    private func startLiveCall() {
        if let asset = voiceService.upgradeAsset(for: languageManager.currentLanguage),
           !asset.state.isBusy
        {
            voiceDownloadItem = AssetItem(asset)
        } else {
            showLiveCall = true
        }
    }

    /// Normalises and saves a newly picked image, then stages it for the next
    /// send. No-ops once ``ChatViewModel/maxStagedAttachments`` is reached.
    private func stageImage(_ image: UIImage) {
        guard viewModel.stagedAttachments.count < ChatViewModel.maxStagedAttachments else {
            return
        }
        Task {
            guard let data = image.jpegData(compressionQuality: 1.0) else { return }
            if let attachment = try? attachmentStore.save(imageData: data, id: UUID()) {
                viewModel.stageAttachment(attachment)
            }
        }
    }
}
