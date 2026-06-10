import SwiftUI

// MARK: - Component

/// Horizontally scrollable option cards presented in the chat feed.
///
/// Tapping an option triggers a two-phase exit animation: sibling cards
/// de-emphasise, then the group collapses height before the selection
/// resolves. This prevents the cards from instantly popping out.
struct OptionsGroupView: View {
    let set: OptionSet
    let onSelect: (String) -> Void
    let onFocusInput: (() -> Void)?

    @Environment(\.colors) private var colors
    @Environment(\.gridBreakpoint) private var breakpoint

    @State private var selectionState: SelectionState = .idle

    /// Tracks the visual state of option selection for the collapse animation.
    private enum SelectionState: Equatable {
        case idle
        case selecting(label: String)
        case collapsing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Sizing.Chat.Gap.message) {
            if let question = set.question {
                Text(question)
                    .typography(Typography.chatMessage)
                    .foregroundStyle(colors.text.standard.base)
                    .padding(.horizontal, breakpoint.inner)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.n12) {
                    ForEach(Array(set.options.enumerated()), id: \.offset) { index, option in
                        optionCard(for: option, index: index)
                    }

                    somethingElseCard
                }
                .padding(.horizontal, breakpoint.inner)
                .padding(.vertical, Spacing.n4)
            }
        }
        .opacity(containerOpacity)
        .animation(.easeInOut(duration: 0.25), value: selectionState)
    }

    // MARK: - Cards

    private func optionCard(for option: OptionItem, index: Int) -> some View {
        AppVisualCard(
            option.label,
            explainer: option.description,
            symbol: option.category?.image ?? Iconography.Illustration.circle,
            variant: cardVariant(forIndex: index)
        ) {
            beginSelection(of: option)
        }
        .opacity(cardOpacity(for: option))
        .scaleEffect(cardScale(for: option))
        .animation(.easeInOut(duration: 0.15), value: selectionState)
    }

    private var somethingElseCard: some View {
        AppVisualCard(
            Localized.Options.somethingElse,
            explainer: Localized.Options.writeOwnAnswer,
            symbol: Image(systemName: "pencil"),
            variant: .neutral
        ) {
            Haptics.light()
            onFocusInput?()
        }
        .opacity(selectionState == .idle ? 1.0 : 0.35)
        .scaleEffect(selectionState == .idle ? 1.0 : 0.95)
        .animation(.easeInOut(duration: 0.15), value: selectionState)
    }

    // MARK: - Selection Logic

    private func beginSelection(of option: OptionItem) {
        guard selectionState == .idle else { return }

        Haptics.light()
        selectionState = .selecting(label: option.label)

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            selectionState = .collapsing

            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            onSelect(option.label)
        }
    }

    // MARK: - Styling Helpers

    private var containerOpacity: Double {
        switch selectionState {
        case .idle: 1.0
        case .selecting: 1.0
        case .collapsing: 0.0
        }
    }

    private func cardOpacity(for option: OptionItem) -> Double {
        switch selectionState {
        case .idle: 1.0
        case .selecting(let label):
            option.label == label ? 1.0 : 0.35
        case .collapsing: 0.0
        }
    }

    private func cardScale(for option: OptionItem) -> CGFloat {
        switch selectionState {
        case .idle: 1.0
        case .selecting(let label):
            option.label == label ? 1.02 : 0.95
        case .collapsing: 0.9
        }
    }

    private func cardVariant(forIndex index: Int) -> AppVisualCardVariant {
        let variants: [AppVisualCardVariant] = [.brand, .warm, .soft]
        return variants[index % variants.count]
    }
}

// MARK: - Previews

#Preview("Option Cards") {
    OptionsGroupView(
        set: OptionSet(
            id: "preview",
            question: "What would you like to focus on?",
            options: [
                OptionItem(
                    label: "Admin work",
                    description: "Catch up on emails and pending approvals",
                    category: .organise
                ),
                OptionItem(
                    label: "Coding task",
                    description: "Work on the Eigin feature branch",
                    category: .create
                ),
                OptionItem(
                    label: "Groceries",
                    description: "Make a shopping list for today",
                    category: .care
                ),
            ]
        ),
        onSelect: { label in print("Selected: \(label)") },
        onFocusInput: {}
    )
    .padding(.vertical, Spacing.n24)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(.systemBackground))
    .resolveTheme()
}
