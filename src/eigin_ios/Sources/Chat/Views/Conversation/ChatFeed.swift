import Factory
import SwiftUI

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
    let splitter: StreamingBlockSplitter?
    @Binding var messageText: String
    let isInputDisabled: Bool
    let onSend: (InteractionMode) -> Void
    let onStop: (() -> Void)?
    let pagination: FeedPagination
    let interactions: FeedInteractions
    let context: FeedContext
    /// When false, the input's action button is hidden regardless of what's available.
    /// Use for surfaces (onboarding, bootstrap) where actions don't apply.
    let showsInputActions: Bool
    /// Item ID whose footer should fade in (set when a streaming turn just ended).
    var lastStreamedItemID: String?
    /// Action for the trailing user-message footer (e.g. retry last turn).
    /// `nil` hides the footer — set while streaming or when retry is unavailable.
    var onUserMessageFooterAction: (() -> Void)?

    @Environment(\.colors) private var colors
    @Environment(\.gridBreakpoint) private var breakpoint
    @Injected(\.speechService) private var speechService
    @State private var isAtBottom = true
    @State private var appendAnchorID: String?
    @State private var selectedError: ConnectionError?
    @State private var presentedPermissionRequest: PermissionRequest?
    @State private var presentedBrowsingRequest: BrowsingRequest?
    @State private var browsingPageReady = false
    @State private var showActionSheet = false
    @State private var showSpacePicker = false
    /// Item IDs that existed before the current streaming turn started.
    /// Items not in this set appeared mid-turn and get `.growIn()` animation.
    @State private var preStreamItemIDs: Set<String> = []
    /// ID of the user message pinned to the top of the viewport for the current turn.
    /// Set on send; overwritten by the next send. The current turn block uses
    /// `viewportHeight` as its `minHeight`, which keeps the user message at the
    /// top until the assistant reply naturally exceeds one viewport.
    @State private var pinnedUserMessageID: String?
    /// Set in `sendMessage` right before `onSend` fires, and consumed by the
    /// `onChange(of: items.last?.id)` handler. Without this gate, pagination
    /// appends (e.g. a `loadNewerMessages` batch ending in a user message)
    /// would be mistaken for a send and pin the message to the top with the
    /// viewport-sized spacer — producing the "new chat" whitespace in windowed
    /// views. Only a real send should trigger the pin.
    @State private var isExpectingSendAppend = false
    /// Measured ScrollView container height. Used as `minHeight` of the
    /// current-turn VStack so the pinned region always fills at least one
    /// viewport.
    @State private var viewportHeight: CGFloat = 0
    @FocusState private var isInputFocused: Bool

    init(
        items: [ChatItem],
        throttler: any StreamThrottling,
        splitter: StreamingBlockSplitter? = nil,
        messageText: Binding<String>,
        isInputDisabled: Bool,
        onSend: @escaping (InteractionMode) -> Void,
        onStop: (() -> Void)? = nil,
        pagination: FeedPagination = FeedPagination(),
        interactions: FeedInteractions = FeedInteractions(),
        context: FeedContext = FeedContext(),
        showsInputActions: Bool = true,
        lastStreamedItemID: String? = nil,
        onUserMessageFooterAction: (() -> Void)? = nil
    ) {
        self.items = items
        self.throttler = throttler
        self.splitter = splitter
        _messageText = messageText
        self.isInputDisabled = isInputDisabled
        self.onSend = onSend
        self.onStop = onStop
        self.pagination = pagination
        self.interactions = interactions
        self.context = context
        self.showsInputActions = showsInputActions
        self.lastStreamedItemID = lastStreamedItemID
        self.onUserMessageFooterAction = onUserMessageFooterAction
    }

    var body: some View {
        feedContent
            .onChange(of: interactions.permissionRequest) { _, new in
                if let new {
                    presentedPermissionRequest = new
                }
            }
            .onChange(of: interactions.browsingRequest) { _, new in
                if let new {
                    presentedBrowsingRequest = new
                    browsingPageReady = false
                }
            }
            .appSheet(
                isPresented: Binding(
                    get: { selectedError != nil },
                    set: { if !$0 { selectedError = nil } }
                ),
                title: selectedError?.title ?? "Error",
                description: selectedError?.suggestion,
                detents: [.medium, .large]
            ) {
                if let error = selectedError {
                    ErrorDetailSheet(error: error)
                }
            }
            .appSheet(
                isPresented: Binding(
                    get: { presentedPermissionRequest != nil },
                    set: { if !$0 { presentedPermissionRequest = nil } }
                ),
                title: Localized.Permission.sheetTitle,
                description: presentedPermissionRequest.map {
                    Localized.Permission.wantsToUseFormat(context.agentName, $0.toolDisplayName)
                },
                detents: [.medium]
            ) {
                PermissionRequestSheetContent(
                    allowOnceLabel: Localized.Permission.allowOnce,
                    allowForChatLabel: Localized.Permission.allowForChat,
                    denyLabel: Localized.Permission.deny,
                    onResponse: { response in
                        interactions.onPermissionResponse?(response)
                    }
                )
            }
            .appSheet(
                isPresented: Binding(
                    get: { presentedBrowsingRequest != nil },
                    set: { if !$0 { presentedBrowsingRequest = nil } }
                ),
                title: Localized.Browsing.title,
                description: browsingPageReady
                    ? Localized.Agent.Status.readingPage(actorName)
                    : Localized.Agent.Status.loadingPage(actorName),
                detents: [.medium],
                showsDismissButton: false,
                onDismiss: {
                    dismissBrowsing(
                        result: .error("User dismissed the browser before request completed.")
                    )
                }
            ) {
                WebBrowsingSheetContent(
                    request: presentedBrowsingRequest!,
                    onComplete: dismissBrowsing,
                    onPageReadyChanged: { ready in browsingPageReady = ready }
                )
            }
            .appSheet(
                isPresented: $showActionSheet,
                title: Localized.Actions.title,
                detents: [.medium]
            ) {
                ActionSheetContent(
                    actions: [
                        ActionItem(
                            label: Localized.Debug.moveToSpaceTitle,
                            icon: Iconography.Brand.security,
                            action: {
                                showActionSheet = false
                                showSpacePicker = true
                            }
                        ),
                    ]
                )
            }
            .appSheet(
                isPresented: $showSpacePicker,
                title: Localized.Debug.moveToSpaceTitle,
                detents: [.medium, .large]
            ) {
                SpacePickerSheetContent(
                    spaces: context.spaces,
                    currentSpaceID: context.currentSpaceID,
                    onSelect: { spaceID in
                        context.onMoveToSpace?(spaceID)
                    }
                )
            } secondary: {
                if context.currentSpaceID != nil {
                    AppButton(
                        Localized.Space.removeFromSpace,
                        variant: .destructive
                    ) {
                        context.onMoveToSpace?(nil)
                    }
                    .padding(.horizontal, Sizing.PageLayout.ContentGrouping.Px.mobile)
                }
            }
            .background(colors.surface.standard.base.ignoresSafeArea())
            .toolbar(.hidden, for: .tabBar)
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
        guard hasMoveToSpace else { return nil }
        return { showActionSheet = true }
    }

    private var actorName: String {
        context.agentName.isEmpty || context.agentName.count > 20 ? "Agent" : context.agentName
    }

    private var isStreaming: Bool {
        throttler.phase == .waiting || throttler.phase == .streaming
    }

    /// The flat item list used when no user turn has been pinned yet.
    ///
    /// If the conversation opens with an agent-initiated message (no user
    /// message first), we apply the same `minHeight` + `.topLeading` frame as
    /// the pinned-turn block. Without it, `.defaultScrollAnchor(.bottom)`
    /// pushes a short opening message to the bottom of the viewport.
    @ViewBuilder private var agentInitiatedBlock: some View {
        let isAgentOpened: Bool = if case .message(_, let role, _) = items.first { role != "user" }
        else { true }
        VStack(alignment: .leading, spacing: Sizing.Chat.Gap.message) {
            ForEach(items) { item in
                itemRow(for: item)
            }
            AppChatBrandMessage {
                StreamingContentView(throttler: throttler, splitter: splitter)
            }
        }
        .frame(
            maxWidth: .infinity,
            minHeight: isAgentOpened ? viewportHeight : 0,
            alignment: .topLeading
        )
    }

    private func dismissBrowsing(result: BrowsingResult) {
        presentedBrowsingRequest = nil
        interactions.onBrowsingComplete?(result)
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

                    let pinnedIndex = pinnedUserMessageID.flatMap { id in
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
                            ForEach(items[pinnedIndex...]) { item in
                                itemRow(for: item)
                            }
                            AppChatBrandMessage {
                                StreamingContentView(throttler: throttler, splitter: splitter)
                            }
                        }
                        .frame(
                            maxWidth: .infinity,
                            minHeight: viewportHeight,
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
                            appendAnchorID = items.last?.id
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
            .defaultScrollAnchor(appendAnchorID != nil ? nil : .bottom)
            .scrollDismissesKeyboard(.interactively)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.visibleRect.maxY >= geometry.contentSize.height - 120
            } action: { _, newValue in
                isAtBottom = newValue
                pagination.onScrollPositionChanged?(newValue)
            }
            // Track the ScrollView container height. Used as `minHeight` of
            // the current-turn block so it always fills at least one viewport.
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.containerSize.height
            } action: { _, newValue in
                viewportHeight = newValue
            }
            .overlay(alignment: .bottom) {
                if !isAtBottom {
                    Button {
                        Haptics.medium()
                        pagination.onSnapToBottom?()
                        // Release the pin so the current-turn block collapses
                        // back into a flat list, then scroll to the bottom.
                        pinnedUserMessageID = nil
                        proxy.scrollTo("bottom-anchor", anchor: .bottom)
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
            .animation(Animations.smooth, value: isAtBottom)
            .safeAreaInset(edge: .bottom, spacing: Spacing.n16) {
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
                    onActionTap: inputAction
                )
                .ignoresSafeArea(.container, edges: .horizontal)
            }
            // Scroll correction on prepend: old first item pinned to top
            .onChange(of: items.first?.id) { oldFirstID, newFirstID in
                if let oldFirstID, oldFirstID != newFirstID,
                   items.contains(where: { $0.id == oldFirstID })
                {
                    proxy.scrollTo(oldFirstID, anchor: .top)
                }
            }
            // On append: either pagination anchor OR pin new user message to top.
            .onChange(of: items.last?.id) { _, _ in
                if let anchorID = appendAnchorID,
                   items.contains(where: { $0.id == anchorID })
                {
                    proxy.scrollTo(anchorID, anchor: .bottom)
                    appendAnchorID = nil
                    return
                }
                // Pin newly-sent user message to the top of the viewport.
                // Gated by `isExpectingSendAppend` so pagination appends that
                // end on a user message don't trigger the viewport-sized spacer.
                guard isExpectingSendAppend,
                      let last = items.last,
                      case .message(let id, let role, _) = last,
                      role == "user",
                      id != pinnedUserMessageID
                else {
                    isExpectingSendAppend = false
                    return
                }
                isExpectingSendAppend = false
                pinnedUserMessageID = id
                // Defer one runloop tick so the current-turn block (with its
                // viewport-sized minHeight) is laid out before we scroll —
                // otherwise `.top` may not yet be reachable.
                DispatchQueue.main.async {
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo(id, anchor: .top)
                    }
                }
            }
            // Track streaming phase for idle-timer and preStream item capture.
            // No auto-scroll here — after the initial pin on send we never
            // touch the scroll position for the rest of the turn.
            .onChange(of: throttler.phase) {
                let phase = throttler.phase
                UIApplication.shared.isIdleTimerDisabled = phase == .waiting || phase == .streaming
                if phase == .waiting {
                    if preStreamItemIDs.isEmpty {
                        preStreamItemIDs = Set(items.map(\.id))
                    }
                } else if phase == .idle {
                    preStreamItemIDs = []
                    isExpectingSendAppend = false
                }
            }
        }
    }

    @ViewBuilder
    private func itemRow(for item: ChatItem) -> some View {
        let isLive =
            throttler.phase != .idle
                && !preStreamItemIDs.isEmpty
                && !preStreamItemIDs.contains(item.id)
        itemView(for: item)
            .growIn(isNew: isLive)
            .id(item.id)
    }

    @ViewBuilder
    private func itemView(for item: ChatItem) -> some View {
        switch item {
        case .message(let id, let role, let content):
            let showsUserMessageFooter =
                role == "user"
                    && id == items.last?.id
                    && !pagination.hasNewerMessages
                    && !isStreaming
                    && onUserMessageFooterAction != nil
            // Retry re-appends the user message via `send`, so it must set the
            // send-append flag — otherwise the pin handler would no-op and the
            // retried message wouldn't anchor to the top of the viewport.
            let retryAction: (() -> Void)? = onUserMessageFooterAction.map { action in
                { isExpectingSendAppend = true; action() }
            }
            ChatMessageView(
                role: role,
                content: content,
                messageID: id,
                showFooter: role == "assistant",
                animateFooter: id == lastStreamedItemID,
                showUserMessageFooter: showsUserMessageFooter,
                onUserMessageFooterAction: retryAction
            )
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
                    action: { selectedError = error }
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
        guard !text.isEmpty else { return }
        isInputFocused = false
        isExpectingSendAppend = true
        onSend(mode)
    }
}

// MARK: - Streaming Content (isolated observation)

/// Renders streaming text or typing indicator.
///
/// This is a separate sub-view so that 60fps `displayedText` changes
/// only re-evaluate this small view — not the entire ForEach of committed messages.
private struct StreamingContentView: View {
    let throttler: any StreamThrottling
    let splitter: StreamingBlockSplitter?

    var body: some View {
        let phase = throttler.phase

        if let splitter {
            blockBasedContent(phase: phase, splitter: splitter)
        }
    }

    @ViewBuilder
    private func blockBasedContent(phase: StreamThrottler.Phase, splitter: StreamingBlockSplitter)
        -> some View
    {
        let blocks = splitter.allBlocks

        // Show all blocks. Only the last block is actively streaming; earlier
        // blocks are already sealed, so they render normally even mid-stream.
        let activeBlockID = phase == .streaming ? blocks.last?.id : nil
        if (phase == .streaming || phase == .done) && !blocks.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.n16) {
                ForEach(blocks) { block in
                    ContentBlockView(
                        block: block,
                        isActivelyStreaming: block.id == activeBlockID
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if phase == .waiting || phase == .streaming {
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
