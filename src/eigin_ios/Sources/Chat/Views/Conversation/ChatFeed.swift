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
    var connectionRequest: CapabilityRequest?
    var onConnectionResolved: ((CapabilityConnectResult) -> Void)?
}

/// What the feed measures of its scroll view to size the viewport.
private struct ViewportMetrics: Equatable {
    var containerHeight: CGFloat
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
    /// Phase of the agent's chat loop — tells the feed when the turn is busy
    /// forming or running tool calls, so the indicator can say so.
    var chatPhase: ChatPhase = .idle
    /// Something outside the chat turn is being prepared (onboarding wrap-up);
    /// shows the indicator with a preparing label even though the loop is idle.
    var isPreparing: Bool = false
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
    /// Scroll view container height; feeds the viewport computation.
    @State private var containerHeight: CGFloat = 0
    @State private var didArmAutoCamera = false
    /// Show gate, appearance clock and stall clock for the thinking indicator.
    @State private var thinkingIndicatorState = ThinkingIndicatorState()
    @FocusState private var isInputFocused: Bool
    /// Floats over the top of the feed; the soft edge softens content beneath it.
    private let headerView: AnyView
    @State private var scrollFrame: CGRect = .zero
    @State private var composerFrame: CGRect = .zero

    private var composerHeight: CGFloat {
        composerFrame.height
    }

    /// The area the composer and keyboard cover at the bottom of the scroll view.
    private var bottomReserve: CGFloat {
        guard !scrollFrame.isEmpty, !composerFrame.isEmpty else { return composerHeight }
        return max(0, scrollFrame.maxY - composerFrame.minY)
    }

    /// The usable viewport: the scroll container (which already excludes the
    /// header's reserved inset) minus the composer zone that overlays it and
    /// the keyboard.
    private func updateViewportHeight() {
        scroll.viewportHeight = max(
            0,
            containerHeight - bottomReserve - Spacing.n16
        )
    }

    init(
        items: [ChatItem],
        throttler: any StreamThrottling,
        streamingItemID: String? = nil,
        chatPhase: ChatPhase = .idle,
        isPreparing: Bool = false,
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
        onUserMessageFooterAction: (() -> Void)? = nil,
        @ViewBuilder header: () -> some View = { EmptyView() }
    ) {
        self.items = items
        self.throttler = throttler
        self.streamingItemID = streamingItemID
        self.chatPhase = chatPhase
        self.isPreparing = isPreparing
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
        headerView = AnyView(header())
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
                // A feed mounted mid-wait (thinking, working, preparing, or
                // parked on the user) arms its own fresh indicator.
                if shouldShowThinkingIndicator {
                    if let activity = indicatorActivity {
                        thinkingIndicatorState.setActivity(activity)
                    }
                    thinkingIndicatorState.setShown(true)
                }
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

    /// True while the conversation is only an agent-initiated opening, with
    /// no user message yet. `ChatFeed` applies the same `minHeight` +
    /// `.topLeading` frame as the pinned-turn block, and the scroll anchor
    /// uses `.top` so a long opening summary shows from its top. Once the user
    /// has replied it is a normal conversation, resting at the latest reply.
    /// A windowed feed starts mid-conversation, so it never counts.
    private var isAgentOpened: Bool {
        if pagination.hasOlderMessages { return false }
        return !items.contains {
            if case .message(_, "user", _, _) = $0 { return true }
            return false
        }
    }

    /// The flat item list used when no user turn has been pinned yet.
    ///
    /// If the conversation opens with an agent-initiated message (no user
    /// message first), `minHeight` + `.topLeading` reserves a viewport-sized
    /// block so the reply streams into place top-aligned rather than the row
    /// sitting bare at the top with the live indicator attached below it.
    private var agentInitiatedBlock: some View {
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
        .animation(.easeIn(duration: 0.2), value: shouldShowThinkingIndicator)
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
                                    // Keep the just-sent message clear of the
                                    // header's soft edge when pinned to the top.
                                    .padding(
                                        .top,
                                        item.id == scroll.pinnedUserMessageID
                                            ? Spacing.n16 : 0
                                    )
                            }
                            typingIndicator
                        }
                        .frame(
                            maxWidth: .infinity,
                            minHeight: scroll.viewportHeight,
                            alignment: .topLeading
                        )
                        // Animates the indicator shrinking out (and the reply
                        // taking its place) instead of popping.
                        .animation(.easeIn(duration: 0.2), value: shouldShowThinkingIndicator)
                    } else {
                        // When the conversation opens with an agent-initiated
                        // message (no user turn yet), the same minHeight +
                        // topLeading treatment as the pinned-turn block reserves
                        // the viewport for the live reply to fill top-aligned.
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
                .padding(.bottom, bottomReserve + Spacing.n16)

                Color.clear.frame(height: 1).id("bottom-anchor")
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                scrollFrame = $0
                updateViewportHeight()
            }
            // Reserve the covered area in the content while scrolling under the composer.
            .ignoresSafeArea(.container, edges: .bottom)
            .ignoresSafeArea(.keyboard)
            .softEdge(header: { headerView }, footerHeight: composerHeight)
            .opacity(isContentReady ? 1 : 0)
            .defaultScrollAnchor(
                scroll.initialAnchor(isAgentOpened: isAgentOpened),
                for: .initialOffset
            )
            // One-time reveal at the bottom anchor; invisible mid-fade.
            .onChange(of: isContentReady) { _, isReady in
                guard isReady,
                      scroll.shouldRevealAtBottom(isAgentOpened: isAgentOpened)
                else { return }
                proxy.scrollTo("bottom-anchor", anchor: .bottom)
            }
            .scrollDismissesKeyboard(.interactively)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.visibleRect.maxY >= geometry.contentSize.height - 120
            } action: { _, newValue in
                scroll.scrollPositionChanged(newValue)
                pagination.onScrollPositionChanged?(newValue)
            }
            // Track the ScrollView container height. Used as `minHeight` of
            // the current-turn block so it always fills at least one viewport.
            .onScrollGeometryChange(for: ViewportMetrics.self) { geometry in
                ViewportMetrics(containerHeight: geometry.containerSize.height)
            } action: { _, newValue in
                containerHeight = newValue.containerHeight
                updateViewportHeight()
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
                    .padding(.bottom, composerHeight + Spacing.n16)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(Animations.smooth, value: scroll.isAtBottom)
            .overlay(alignment: .bottom) {
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
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                    composerFrame = $0
                    updateViewportHeight()
                }
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
            // The indicator mounts/remounts only on this edge, so a stall
            // (options, permissions) never tears it down or restarts it.
            .onChange(of: shouldShowThinkingIndicator) { _, shouldShow in
                thinkingIndicatorState.setShown(shouldShow)
            }
            // Stalls park the activity clock; resuming restarts it.
            .onChange(of: isAwaitingUserInput) { _, stalled in
                thinkingIndicatorState.setStalled(stalled)
            }
            // Activity swaps swap the copy and restart its ladder — never
            // the indicator itself.
            .onChange(of: indicatorActivity) { _, activity in
                if let activity {
                    thinkingIndicatorState.setActivity(activity)
                }
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

    /// Shown while the turn has started but no text has arrived yet, and
    /// stays through stalls (options, permissions) with its waiting copy —
    /// one fresh cycle per appearance.
    @ViewBuilder private var typingIndicator: some View {
        // `shouldShowThinkingIndicator` is re-evaluated at render time so
        // the delayed task can never show the indicator after the turn ended.
        if shouldShowThinkingIndicator, thinkingIndicatorState.isShown,
           let shownAt = thinkingIndicatorState.shownAt
        {
            AppChatBrandMessage {
                ThinkingIndicator(
                    shownAt: shownAt,
                    clockStart: thinkingIndicatorState.clockStart,
                    priorElapsed: thinkingIndicatorState.priorElapsed,
                    activity: thinkingIndicatorState.activity,
                    isStalled: isAwaitingUserInput
                )
                // Entry is part of the indicator's own timeline; removal scales
                // it away so the reply takes its place.
                .transition(.asymmetric(
                    insertion: .identity,
                    removal: .scale(scale: 0, anchor: .leading)
                        .combined(with: .opacity)
                        .animation(.easeIn(duration: 0.2))
                ))
            }
        }
    }

    /// What the agent is doing right now, or nil when nothing new is
    /// visibly happening and the turn is quiet. `isPreparing` wins over a
    /// settled chat phase; tool work wins over the streaming throttler.
    private var indicatorActivity: ThinkingActivity? {
        if isPreparing { return .preparing }
        if isAwaitingUserInput { return nil }
        switch chatPhase {
        case .streamingTools, .readyToExecute, .executingTools:
            return .working
        case .streamingProse, .idle, .done:
            return isThinking ? .thinking : nil
        }
    }

    /// Turn waiting on the model, with nothing parked on the user. Also
    /// covers the quiet stretch where everything streamed so far is already
    /// displayed but the stream is open — the model may be reasoning or
    /// forming long tool calls before its next visible output.
    private var isThinking: Bool {
        let waiting = throttler.phase == .waiting
            || (throttler.phase == .streaming
                && (throttler.displayedText.isEmpty || throttler.hasCaughtUp))
        return waiting && !isAwaitingUserInput
    }

    /// Turn mid-flight but parked waiting on the user — options/flashcards,
    /// permission or browsing prompts.
    private var isAwaitingUserInput: Bool {
        if case .options = items.last { return true }
        return interactions.permissionRequest != nil
            || interactions.browsingRequest != nil
            || interactions.connectionRequest != nil
    }

    /// Whether a thinking indicator belongs on screen: the turn is
    /// mid-flight (thinking or working), preparing something, or parked
    /// on the user.
    private var shouldShowThinkingIndicator: Bool {
        indicatorActivity != nil || isAwaitingUserInput
    }

    private func itemRow(for item: ChatItem) -> some View {
        ChatFeedRow(
            item: item,
            isStreamingRow: item.id == streamingItemID && throttler.phase == .streaming,
            showsUserMessageFooter:
            item.id == items.last?.id
                && !pagination.hasNewerMessages
                && !isStreaming
                && onUserMessageFooterAction != nil,
            onUserMessageFooterAction: onUserMessageFooterAction.map { action in
                // Retry re-appends the user message via `send`, so it declares
                // the `.sending` intent — otherwise the pin handler would no-op
                // and the retried message wouldn't anchor to the viewport top.
                { scroll.declareSending(); action() }
            },
            onOptionSelected: interactions.onOptionSelected,
            onFocusInput: { isInputFocused = true },
            onSelectError: { sheets.selectedError = $0 }
        )
        .growIn(isNew: scroll.isLiveRow(item.id, phase: throttler.phase))
        .id(item.id)
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
