import Factory
import SwiftUI
import UIKit

/// Pagination and scroll-tracking callbacks for ``ChatFeed``.
struct FeedPagination {
    var hasOlderMessages: Bool = false
    var onLoadMore: (() -> Void)?
    var hasNewerMessages: Bool = false
    var onLoadNewer: (() -> Void)?
    var onSnapToBottom: (() -> Void)?
    var onScrollPositionChanged: ((Bool) -> Void)?
}

/// Agent and space context passed through to ``ChatInputBar``.
struct FeedContext {
    var agentName: String = ""
    var spaces: [SpaceSnapshot] = []
    var currentSpaceID: UUID?
    var onMoveToSpace: ((UUID?) -> Void)?
    /// Whether the current model supports image input.
    var supportsVision: Bool = false
    /// Staged image attachments waiting to be sent with the next message.
    var stagedAttachments: [MessageAttachment] = []
    /// Called when the user picks an image (from library or camera) to stage.
    var onStageImage: ((UIImage) -> Void)?
    /// Called when the user removes a staged attachment.
    var onRemoveStagedAttachment: ((MessageAttachment) -> Void)?
}

/// Pending interaction requests passed through to ``ChatInputBar``.
struct FeedInteractions {
    var permissionRequest: PermissionRequest?
    var onPermissionResponse: ((PermissionResponse) -> Void)?
    var browsingRequest: BrowsingRequest?
    var onBrowsingComplete: ((BrowsingResult) -> Void)?
    var onOptionSelected: ((String) -> Void)?
    var onOptionDismissed: (() -> Void)?
}

/// A shared scrollable chat feed with input bar.
///
/// Renders a list of `ChatItem`s plus optional streaming content, and provides
/// an input bar at the bottom.
struct ChatFeed: View {
    let items: [ChatItem]
    let throttler: any StreamThrottling
    @Binding var messageText: String
    let isInputDisabled: Bool
    var autoStartDictation = false
    var autoShowCamera = false
    let onSend: (InteractionMode) -> Void
    let onStop: (() -> Void)?
    let pagination: FeedPagination
    let interactions: FeedInteractions
    let context: FeedContext
    /// When false, the input's action button is hidden regardless of what's available.
    /// Use for surfaces (onboarding, bootstrap) where actions don't apply.
    let showsInputActions: Bool
    /// When false, icebreaker starters never appear. Set for agent-initiated
    /// surfaces (onboarding, bootstrap) where the agent opens the turn, so the
    /// user isn't the one starting the conversation.
    let allowsIcebreakers: Bool
    /// Whether the feed's messages have finished loading. While false, icebreakers
    /// stay hidden so they don't flash on an existing chat whose messages are still
    /// being fetched (the feed is momentarily empty before they populate).
    let isLoaded: Bool
    /// Whether the messages' markdown has been parsed. The feed fades in once it has, so
    /// the first frame is the settled layout.
    let isContentReady: Bool
    /// Item ID of the streaming message. Rendered as an ordinary row so committing it
    /// updates the row in place.
    var streamingItemID: String?
    /// Action for the trailing user-message footer (e.g. retry last turn).
    /// `nil` hides the footer — set while streaming or when retry is unavailable.
    var onUserMessageFooterAction: (() -> Void)?

    @Environment(\.colors) private var colors
    @Environment(\.gridBreakpoint) private var breakpoint
    @Environment(\.scenePhase) private var scenePhase
    @Injected(\.speechService) private var speechService
    /// Presentation state for every sheet, picker, and cover the feed hosts.
    /// Owned here because the feed's rows and input trigger them; presented by
    /// the ``ChatFeedSheets`` modifier.
    @State private var sheets = ChatFeedSheetState()
    /// Owns scroll position, the current-turn pin, and grow-in tracking.
    @State private var scroll = FeedScrollCoordinator()
    @State private var didArmAutoCamera = false
    @FocusState private var isInputFocused: Bool

    init(
        items: [ChatItem],
        throttler: any StreamThrottling,
        streamingItemID: String? = nil,
        messageText: Binding<String>,
        isInputDisabled: Bool,
        autoStartDictation: Bool = false,
        autoShowCamera: Bool = false,
        onSend: @escaping (InteractionMode) -> Void,
        onStop: (() -> Void)? = nil,
        pagination: FeedPagination = FeedPagination(),
        interactions: FeedInteractions = FeedInteractions(),
        context: FeedContext = FeedContext(),
        showsInputActions: Bool = true,
        allowsIcebreakers: Bool = true,
        isLoaded: Bool = true,
        isContentReady: Bool = true,
        onUserMessageFooterAction: (() -> Void)? = nil
    ) {
        self.items = items
        self.throttler = throttler
        self.streamingItemID = streamingItemID
        _messageText = messageText
        self.isInputDisabled = isInputDisabled
        self.autoStartDictation = autoStartDictation
        self.autoShowCamera = autoShowCamera
        self.onSend = onSend
        self.onStop = onStop
        self.pagination = pagination
        self.interactions = interactions
        self.context = context
        self.showsInputActions = showsInputActions
        self.allowsIcebreakers = allowsIcebreakers
        self.isLoaded = isLoaded
        self.isContentReady = isContentReady
        self.onUserMessageFooterAction = onUserMessageFooterAction
    }

    var body: some View {
        feedContent
            .modifier(ChatFeedSheets(
                state: sheets,
                context: context,
                interactions: interactions
            ))
            .background(colors.surface.standard.base.ignoresSafeArea())
            .toolbar(.hidden, for: .tabBar)
            .onAppear {
                armAutoCamera()
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                armAutoCamera()
            }
            .onDisappear {
                UIApplication.shared.isIdleTimerDisabled = false
                speechService.stop()
            }
    }

    /// Closure for the input's action button, or `nil` to hide it.
    /// Returns `nil` when the surface opts out or when no individual action is available.
    private var inputAction: (() -> Void)? {
        guard showsInputActions else { return nil }
        let hasMoveToSpace = context.onMoveToSpace != nil && !context.spaces.isEmpty
        let canAttachImage = context.supportsVision
            && context.stagedAttachments.count < ChatViewModel.maxStagedAttachments
        guard hasMoveToSpace || canAttachImage else { return nil }
        return { sheets.showActionSheet = true }
    }

    private var isStreaming: Bool {
        throttler.phase == .waiting || throttler.phase == .streaming
    }

    /// Whether to show the icebreaker starters: only on a truly blank slate —
    /// no messages, no staged attachments, an empty composer, an enabled input,
    /// and nothing streaming.
    private var showsIcebreakers: Bool {
        allowsIcebreakers
            && isLoaded
            && items.isEmpty
            && !isInputDisabled
            && !isStreaming
            && context.stagedAttachments.isEmpty
            && messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The flat item list used when no user turn has been pinned yet.
    ///
    /// If the conversation opens with an agent-initiated message (no user
    /// message first), we apply the same `minHeight` + `.topLeading` frame as
    /// the pinned-turn block. Without it, `.defaultScrollAnchor(.bottom)`
    /// pushes a short opening message to the bottom of the viewport.
    @ViewBuilder private var agentInitiatedBlock: some View {
        let isAgentOpened: Bool = if case .message(_, let role, _, _) = items
            .first { role != "user" }
        else { true }
        VStack(alignment: .leading, spacing: Sizing.Chat.Gap.message) {
            ForEach(rows(items[...])) { item in
                itemRow(for: item)
            }
            typingIndicator
        }
        .frame(
            maxWidth: .infinity,
            minHeight: isAgentOpened ? scroll.viewportHeight : 0,
            alignment: .topLeading
        )
    }

    private var feedContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Sizing.Chat.Gap.message) {
                    if pagination.hasOlderMessages {
                        Button {
                            pagination.onLoadMore?()
                        } label: {
                            Label("Load older messages", systemImage: "chevron.up")
                                .typography(Typography.miniLabel)
                                .foregroundStyle(colors.text.standard.muted)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, Spacing.n8)
                        }
                    }

                    let pinnedIndex = scroll.pinnedUserMessageID.flatMap { id in
                        items.firstIndex(where: { $0.id == id })
                    }

                    if let pinnedIndex {
                        // History (everything before the pinned user message)
                        // renders normally inside the outer VStack.
                        ForEach(items[..<pinnedIndex]) { item in
                            itemRow(for: item)
                        }
                        // Current turn (pinned user msg + trailing items + streaming)
                        // is wrapped in its own VStack with `minHeight = viewportHeight`,
                        // top-aligned. Empty space lives inside the block when the
                        // reply is short, so the user message can't be scrolled off.
                        // When the reply naturally exceeds one viewport, the block
                        // grows past `minHeight` and the user can scroll through it.
                        VStack(alignment: .leading, spacing: Sizing.Chat.Gap.message) {
                            ForEach(rows(items[pinnedIndex...])) { item in
                                itemRow(for: item)
                            }
                            typingIndicator
                        }
                        .frame(
                            maxWidth: .infinity,
                            minHeight: scroll.viewportHeight,
                            alignment: .topLeading
                        )
                    } else {
                        // When the conversation opens with an agent-initiated message
                        // (no user turn yet), apply the same minHeight + topLeading
                        // treatment as the pinned-turn block. Without it,
                        // `.defaultScrollAnchor(.bottom)` pushes a short opening
                        // message to the bottom of the viewport.
                        agentInitiatedBlock
                    }

                    if pagination.hasNewerMessages {
                        Button {
                            scroll.beginLoadNewer(lastItemID: items.last?.id)
                            pagination.onLoadNewer?()
                        } label: {
                            Label("Load newer messages", systemImage: "chevron.down")
                                .typography(Typography.miniLabel)
                                .foregroundStyle(colors.text.standard.muted)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, Spacing.n8)
                        }
                    }
                }

                Color.clear.frame(height: 1).id("bottom-anchor")
            }
            .opacity(isContentReady ? 1 : 0)
            .defaultScrollAnchor(scroll.keepsBottomAnchor ? .bottom : nil)
            .scrollDismissesKeyboard(.interactively)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.visibleRect.maxY >= geometry.contentSize.height - 120
            } action: { _, newValue in
                scroll.scrollPositionChanged(newValue)
                pagination.onScrollPositionChanged?(newValue)
            }
            // Track the ScrollView container height. Used as `minHeight` of
            // the current-turn block so it always fills at least one viewport.
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.containerSize.height
            } action: { _, newValue in
                scroll.viewportHeight = newValue
            }
            .overlay(alignment: .bottom) {
                if !scroll.isAtBottom {
                    Button {
                        Haptics.medium()
                        pagination.onSnapToBottom?()
                        scroll.snapToBottom(proxy: proxy)
                    } label: {
                        Image(systemName: "arrow.down")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(colors.text.standard.muted)
                            .frame(width: 36, height: 36)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay(
                                Circle()
                                    .stroke(colors.text.standard.muted.opacity(0.2), lineWidth: 0.5)
                            )
                    }
                    .padding(.bottom, Spacing.n16)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(Animations.smooth, value: scroll.isAtBottom)
            .safeAreaInset(edge: .bottom, spacing: Spacing.n16) {
                VStack(spacing: 0) {
                    if showsIcebreakers {
                        IcebreakerFeed(
                            groups: IcebreakerSelection.groups(),
                            onSelect: { prompt in
                                messageText = prompt
                                sendMessage()
                            }
                        )
                        // Same gap the staged-attachments strip leaves above the input.
                        .padding(.bottom, Spacing.n8)
                        .transition(.opacity)
                    }
                    if !context.stagedAttachments.isEmpty {
                        StagedAttachmentsView(
                            attachments: context.stagedAttachments,
                            onRemove: { attachment in
                                context.onRemoveStagedAttachment?(attachment)
                            }
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    ChatInputBar(
                        text: $messageText,
                        isDisabled: isInputDisabled,
                        onSend: { mode in sendMessage(mode: mode) },
                        onStop: onStop,
                        isFocused: $isInputFocused,
                        spaces: context.spaces,
                        currentSpaceID: context.currentSpaceID,
                        onMoveToSpace: context.onMoveToSpace,
                        agentName: context.agentName,
                        permissionRequest: interactions.permissionRequest,
                        onPermissionResponse: interactions.onPermissionResponse,
                        onActionTap: inputAction,
                        hasStagedAttachments: !context.stagedAttachments.isEmpty,
                        autoStartDictation: autoStartDictation
                    )
                }
                .animation(Animations.smooth, value: context.stagedAttachments.isEmpty)
                .animation(Animations.smooth, value: showsIcebreakers)
                .ignoresSafeArea(.container, edges: .horizontal)
            }
            // Scroll correction on prepend: old first item pinned to top.
            .onChange(of: items.first?.id) { oldFirstID, newFirstID in
                scroll.restoreScrollAfterOlderLoad(
                    oldFirstID: oldFirstID, newFirstID: newFirstID, items: items, proxy: proxy
                )
            }
            // On append: either pagination anchor OR pin new user message to top.
            .onChange(of: items.last?.id) { _, _ in
                scroll.applyScrollForNewItems(items, proxy: proxy)
            }
            // Track streaming phase for idle-timer and preStream item capture.
            // No auto-scroll here — after the initial pin on send we never
            // touch the scroll position for the rest of the turn.
            .onChange(of: throttler.phase) {
                let phase = throttler.phase
                UIApplication.shared.isIdleTimerDisabled = phase == .waiting || phase == .streaming
                scroll.phaseChanged(to: phase, items: items)
            }
        }
    }

    /// Appends the live assistant turn as a message row with the ID it keeps once
    /// committed, so committing diffs the row in place and its parsed markdown survives.
    private func rows(_ items: ArraySlice<ChatItem>) -> [ChatItem] {
        var rows = Array(items)
        guard let streamingItemID,
              throttler.phase == .streaming || throttler.phase == .done,
              !throttler.displayedText.isEmpty,
              !rows.contains(where: { $0.id == streamingItemID })
        else { return rows }
        rows.append(
            .message(id: streamingItemID, role: "assistant", content: throttler.displayedText)
        )
        return rows
    }

    /// Shown while the turn has started but no text has arrived yet.
    @ViewBuilder private var typingIndicator: some View {
        if throttler.phase == .waiting
            || (throttler.phase == .streaming && throttler.displayedText.isEmpty)
        {
            AppChatBrandMessage {
                TypingIndicator()
                    .transition(
                        .asymmetric(
                            insertion: .opacity.animation(.easeIn(duration: Animations.fast)),
                            removal: .identity
                        )
                    )
            }
        }
    }

    private func itemRow(for item: ChatItem) -> some View {
        itemView(for: item)
            .growIn(isNew: scroll.isLiveRow(item.id, phase: throttler.phase))
            .id(item.id)
    }

    @ViewBuilder
    private func itemView(for item: ChatItem) -> some View {
        switch item {
        case .message(let id, let role, let content, let attachments):
            let showsUserMessageFooter =
                role == "user"
                    && id == items.last?.id
                    && !pagination.hasNewerMessages
                    && !isStreaming
                    && onUserMessageFooterAction != nil
            // Retry re-appends the user message via `send`, so it declares the
            // `.sending` intent — otherwise the pin handler would no-op and the
            // retried message wouldn't anchor to the top of the viewport.
            let retryAction: (() -> Void)? = onUserMessageFooterAction.map { action in
                { scroll.declareSending(); action() }
            }
            let isStreamingRow = id == streamingItemID && throttler.phase == .streaming
            ChatMessageView(
                role: role,
                content: content,
                attachments: attachments,
                messageID: id,
                isActivelyStreaming: isStreamingRow,
                showFooter: role == "assistant" && !isStreamingRow,
                showUserMessageFooter: showsUserMessageFooter,
                onUserMessageFooterAction: retryAction
            )
            .equatable()
        case .typing:
            TypingIndicator()
                .padding(.horizontal, breakpoint.inner)
        case .status(_, let text):
            HStack(spacing: Spacing.n8) {
                ProgressView()
                Text(text)
                    .typography(Typography.note)
                    .foregroundStyle(colors.text.standard.muted)
            }
            .padding(.horizontal, breakpoint.inner)
        case .error(_, let error):
            if error.recovery == .purchaseEiginRelayCredits {
                CreditsRecoveryCard(error: error)
                    .padding(.horizontal, breakpoint.inner)
            } else {
                AppCard(
                    error.title,
                    explainer: error.suggestion,
                    action: { sheets.selectedError = error }
                )
                .padding(.horizontal, breakpoint.inner)
            }
        case .toolGroup(_, let tools):
            ToolGroupView(tools: tools)
                .padding(.horizontal, breakpoint.inner)
        case .options(_, let set):
            OptionsGroupView(
                set: set,
                onSelect: { interactions.onOptionSelected?($0) },
                onFocusInput: { isInputFocused = true }
            )
        case .compaction(_, let progress, let summary):
            CompactionDivider(progress: progress, summary: summary)
                .padding(.horizontal, breakpoint.inner)
        }
    }

    private func sendMessage(mode: InteractionMode = .text) {
        let text = messageText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty || !context.stagedAttachments.isEmpty else { return }
        isInputFocused = false
        scroll.declareSending()
        onSend(mode)
    }

    /// Opens the auto-started camera once, and only once the scene is active —
    /// mirrors the dictation arming so a widget launch presents sheets only
    /// after the foreground transition finishes.
    private func armAutoCamera() {
        guard autoShowCamera, !didArmAutoCamera, scenePhase == .active else { return }
        didArmAutoCamera = true
        sheets.showCamera = true
    }
}
