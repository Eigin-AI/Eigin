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
    /// Item ID whose footer should fade in (set when a streaming turn just ended).
    var lastStreamedItemID: String?

    @Environment(\.colors) private var colors
    @Injected(\.speechService) private var speechService
    @State private var isAtBottom = true
    @State private var appendAnchorID: String?
    @State private var selectedError: ConnectionError?
    /// Item IDs that existed before the current streaming turn started.
    /// Items not in this set appeared mid-turn and get `.growIn()` animation.
    @State private var preStreamItemIDs: Set<String> = []
    /// ID of the user message pinned to the top of the viewport for the current turn.
    /// Set on send; overwritten by the next send. The current turn block uses
    /// `viewportHeight` as its `minHeight`, which keeps the user message at the
    /// top until the assistant reply naturally exceeds one viewport.
    @State private var pinnedUserMessageID: String?
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
        lastStreamedItemID: String? = nil
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
        self.lastStreamedItemID = lastStreamedItemID
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if pagination.hasOlderMessages {
                        Button {
                            pagination.onLoadMore?()
                        } label: {
                            Label("Load older messages", systemImage: "chevron.up")
                                .font(Typography.caption)
                                .foregroundStyle(colors.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, Spacing.sm)
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
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(items[pinnedIndex...]) { item in
                                itemRow(for: item)
                            }
                            StreamingContentView(throttler: throttler, splitter: splitter)
                        }
                        .frame(
                            maxWidth: .infinity,
                            minHeight: viewportHeight,
                            alignment: .topLeading
                        )
                    } else {
                        ForEach(items) { item in
                            itemRow(for: item)
                        }
                        StreamingContentView(throttler: throttler, splitter: splitter)
                    }

                    if pagination.hasNewerMessages {
                        Button {
                            appendAnchorID = items.last?.id
                            pagination.onLoadNewer?()
                        } label: {
                            Label("Load newer messages", systemImage: "chevron.down")
                                .font(Typography.caption)
                                .foregroundStyle(colors.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, Spacing.sm)
                        }
                    }
                }
                .padding()

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
                            .foregroundStyle(colors.textSecondary)
                            .frame(width: 36, height: 36)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay(
                                Circle()
                                    .stroke(colors.textSecondary.opacity(0.2), lineWidth: 0.5)
                            )
                    }
                    .padding(.bottom, Spacing.sm)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(Animations.smooth, value: isAtBottom)
            .safeAreaInset(edge: .bottom, spacing: Spacing.md) {
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
                    browsingRequest: interactions.browsingRequest,
                    onBrowsingComplete: interactions.onBrowsingComplete
                )
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
                guard let last = items.last,
                      case .message(let id, let role, _) = last,
                      role == "user",
                      id != pinnedUserMessageID
                else { return }
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
                }
            }
        }
        .sheet(
            isPresented: Binding(
                get: { selectedError != nil },
                set: { if !$0 { selectedError = nil } }
            )
        ) {
            if let error = selectedError {
                ErrorDetailSheet(error: error)
            }
        }
        .background(colors.background.ignoresSafeArea())
        .toolbar(.hidden, for: .tabBar)
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            speechService.stop()
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
            ChatMessageView(
                role: role,
                content: content,
                messageID: id,
                showFooter: role == "assistant",
                animateFooter: id == lastStreamedItemID
            )
        case .typing:
            TypingIndicator()
        case .status(_, let text):
            HStack(spacing: Spacing.sm) {
                ProgressView()
                Text(text)
                    .font(Typography.callout)
                    .foregroundStyle(colors.textSecondary)
            }
            .padding(.horizontal)
        case .error(_, let error):
            Button {
                selectedError = error
            } label: {
                Label(error.title, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(colors.destructive)
                    .font(Typography.body.weight(.medium))
            }
            .buttonStyle(.plain)
        case .toolGroup(_, let tools):
            ToolGroupView(tools: tools)
        case .compaction(_, let progress, let summary):
            CompactionDivider(progress: progress, summary: summary)
        }
    }

    private func sendMessage(mode: InteractionMode = .text) {
        let text = messageText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        isInputFocused = false
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

        // Show all blocks - the last one is the active one being streamed
        if (phase == .streaming || phase == .done) && !blocks.isEmpty {
            ElasticContainer(isActive: phase == .streaming) {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    ForEach(blocks) { block in
                        ContentBlockView(block: block)
                    }
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
