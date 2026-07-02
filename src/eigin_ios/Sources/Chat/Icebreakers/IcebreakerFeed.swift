import SwiftUI

/// Suggested openers shown on an empty chat, just above the input bar.
///
/// Presents a horizontally scrollable row of use-case chips, aligned to the
/// same leading edge as the input bar's pill. Tapping a chip opens an
/// ``AppSheet`` titled with the group's name, listing that group's
/// icebreakers as rows (matching ``ActionSheetContent``'s row style). Tapping
/// a row hands its full prompt back via ``onSelect`` and dismisses the sheet.
struct IcebreakerFeed: View {
    let groups: [IcebreakerGroup]
    /// Called with the tapped icebreaker's resolved prompt text.
    let onSelect: (String) -> Void

    @State private var isSheetPresented = false
    /// The group backing the sheet's content. Only updated when opening a new
    /// sheet — left in place while dismissing, so the title and rows don't
    /// flash empty during the close animation.
    @State private var selectedGroup: IcebreakerGroup?

    var body: some View {
        chips
            .appSheet(
                isPresented: $isSheetPresented,
                title: selectedGroup?.label.resolved ?? "",
                detents: [.medium, .large]
            ) {
                if let selectedGroup {
                    IcebreakerSheetContent(icebreakers: selectedGroup.icebreakers) { prompt in
                        isSheetPresented = false
                        onSelect(prompt)
                    }
                }
            }
    }

    /// Same horizontal inset the input bar's pill sits at (`AppChatInput`'s
    /// `Spacing.n8` outer padding), so the chips align with it.
    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.n8) {
                ForEach(groups) { group in
                    AppButton(group.label.resolved, variant: .secondary, size: .small) {
                        Haptics.light()
                        selectedGroup = group
                        isSheetPresented = true
                    }
                }
            }
            .padding(.horizontal, Spacing.n8)
        }
    }
}

// MARK: - Sheet content

/// A list of icebreaker rows for one group, styled like ``ActionSheetContent``.
private struct IcebreakerSheetContent: View {
    let icebreakers: [IcebreakerPrompt]
    let onSelect: (String) -> Void

    var body: some View {
        VStack(spacing: contentGap) {
            ForEach(icebreakers) { ice in
                AppSubtleActionButton(
                    ice.title.resolved,
                    icon: Image(systemName: "chevron.right")
                ) {
                    onSelect(ice.prompt.resolved)
                }
                .padding(.horizontal, contentPx)
            }
        }
    }
}

private let contentPx = Sizing.PageLayout.ContentGrouping.Px.mobile
private let contentGap = Sizing.PageLayout.ContentGrouping.gap

// MARK: - Preview

/// Anchors the feed to the bottom of the screen, above a mock input pill, to
/// mirror how it sits on an empty chat.
private struct IcebreakerFeedPreview: View {
    @Environment(\.colors) private var colors

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            IcebreakerFeed(
                groups: IcebreakerSelection.groups(),
                onSelect: { print("Selected prompt: \($0)") }
            )
            .padding(.bottom, Spacing.n8)
            mockInput
        }
        .padding(.bottom, Spacing.n16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(colors.surface.standard.base)
    }

    /// A stand-in for the chat input pill, so the feed previews in context.
    private var mockInput: some View {
        HStack {
            Text("Chat with Eigin")
                .typography(Typography.chatMessage)
                .foregroundStyle(colors.text.standard.muted)
            Spacer()
        }
        .padding(.horizontal, Spacing.n24)
        .frame(height: Sizing.Button.Height.large)
        .background(colors.surface.standard.alternative)
        .clipShape(RoundedRectangle(cornerRadius: Radius.full))
        .padding(.horizontal, Spacing.n8)
    }
}

#Preview("Light") {
    IcebreakerFeedPreview()
        .resolveTheme()
}

#Preview("Dark") {
    IcebreakerFeedPreview()
        .resolveTheme()
        .environment(\.colorScheme, .dark)
}
