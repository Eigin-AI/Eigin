import SwiftUI

/// One feed row for a `ChatItem` — the single place items become views.
/// Used by ``ChatFeed`` and by the dev-only screenshot canvas, which composes
/// finished turns without a live chat loop.
struct ChatFeedRow: View {
    let item: ChatItem
    /// Whether this row is the message currently streaming in.
    var isStreamingRow: Bool = false
    /// Whether to show the trailing user-message footer (e.g. retry last turn).
    var showsUserMessageFooter: Bool = false
    /// Action for the trailing user-message footer; shown when
    /// `showsUserMessageFooter` is true.
    var onUserMessageFooterAction: (() -> Void)?
    var onOptionSelected: ((String) -> Void)?
    var onFocusInput: (() -> Void)?
    var onSelectError: ((ConnectionError) -> Void)?

    @Environment(\.colors) private var colors
    @Environment(\.gridBreakpoint) private var breakpoint

    var body: some View {
        switch item {
        case .message(let id, let role, let content, let attachments):
            ChatMessageView(
                role: role,
                content: content,
                attachments: attachments,
                messageID: id,
                isActivelyStreaming: isStreamingRow,
                showFooter: role == "assistant" && !isStreamingRow,
                showUserMessageFooter: showsUserMessageFooter,
                onUserMessageFooterAction: onUserMessageFooterAction
            )
            .equatable()
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
                    action: { onSelectError?(error) }
                )
                .padding(.horizontal, breakpoint.inner)
            }
        case .toolGroup(_, let tools):
            ToolGroupView(tools: tools)
                .padding(.horizontal, breakpoint.inner)
        case .options(_, let set):
            OptionsGroupView(
                set: set,
                onSelect: { onOptionSelected?($0) },
                onFocusInput: { onFocusInput?() }
            )
        case .compaction(_, let progress, let summary):
            CompactionDivider(progress: progress, summary: summary)
                .padding(.horizontal, breakpoint.inner)
        }
    }
}
