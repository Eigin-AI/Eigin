import SwiftUI

/// The tool-permission disclosure sentence, styled for the sheet header's
/// description slot: bold tool name for the generic case, tinted italic quoted
/// value for the inline case.
///
/// Pass to ``appSheet`` via `descriptionContent:` so it inherits the header's
/// description spacing and inset.
struct PermissionDisclosureText: View {
    let agentName: String
    let toolDisplayName: String
    let disclosure: ToolDisclosure?

    @Environment(\.colors) private var colors

    var body: some View {
        Text(sentence)
            .typography(Typography.description)
            .foregroundStyle(colors.text.standard.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sentence: AttributedString {
        let presentation = ToolDisclosurePresentation(
            agentName: agentName,
            toolDisplayName: toolDisplayName,
            disclosure: disclosure
        )
        switch presentation.kind {
        case .generic(let agent, let tool):
            var s = AttributedString("\(Localized.Permission.wantsToUseFormat(agent, tool)).")
            if let range = s.range(of: tool) {
                s[range].inlinePresentationIntent = .stronglyEmphasized
            }
            return s
        case .actionOnly(let text):
            return AttributedString("\(text).")
        case .inline(let text, let value):
            var s = AttributedString("\(text) ")
            var quoted = AttributedString("\"\(value)\"")
            quoted.foregroundColor = colors.accent
            quoted.inlinePresentationIntent = .emphasized
            s += quoted
            s += AttributedString(".")
            return s
        case .block(let text, _):
            return AttributedString("\(text):")
        }
    }
}

/// Content for a tool-permission prompt: an optional scrollable payload card
/// followed by the response buttons.
///
/// The disclosure sentence is presented separately via ``appSheet``'s
/// `descriptionContent:` (see ``PermissionDisclosureText``) so it reads as the
/// sheet's description. This view owns only the content group.
struct PermissionRequestSheetContent: View {
    let agentName: String
    let toolDisplayName: String
    let disclosure: ToolDisclosure?
    let allowOnceLabel: String
    let allowForChatLabel: String
    let denyLabel: String
    let onResponse: (PermissionResponse) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var didRespond = false

    private var blockValue: String? {
        ToolDisclosurePresentation(
            agentName: agentName,
            toolDisplayName: toolDisplayName,
            disclosure: disclosure
        ).blockValue
    }

    var body: some View {
        // Payload card and buttons are separate groups: the card sits apart,
        // the buttons are grouped tightly together.
        VStack(spacing: Sizing.PageLayout.pyTop) {
            if let block = blockValue {
                PermissionPayloadCard(text: block)
                    .padding(.horizontal, contentPx)
            }

            VStack(spacing: contentGap) {
                AppButton(allowOnceLabel, variant: .primary) {
                    respond(.allowOnce)
                }
                AppButton(allowForChatLabel, variant: .spot) {
                    respond(.allowForChat)
                }
                AppButton(denyLabel, variant: .destructive) {
                    respond(.deny)
                }
            }
            .padding(.horizontal, contentPx)
        }
        .onDisappear {
            if !didRespond {
                onResponse(.deny)
            }
        }
    }

    private func respond(_ response: PermissionResponse) {
        didRespond = true
        onResponse(response)
        dismiss()
    }
}

/// A bounded, scrollable card for a long payload. Height-capped so the sheet
/// stays within its detent; a bottom fade signals more content when the value
/// overflows the card.
private struct PermissionPayloadCard: View {
    let text: String

    @Environment(\.colors) private var colors
    @State private var contentHeight: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0

    /// ~6 lines of body text.
    private let maxHeight: CGFloat = 150

    private var isOverflowing: Bool {
        contentHeight > viewportHeight + 1
    }

    var body: some View {
        ScrollView {
            Text(text)
                .typography(Typography.description)
                .foregroundStyle(colors.text.standard.base)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Spacing.n16)
                // Extra inset only while scrolling, so the last line clears the fade.
                .padding(.bottom, isOverflowing ? Spacing.n16 : 0)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                    contentHeight = $0
                }
        }
        .scrollDisabled(!isOverflowing)
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxHeight: maxHeight)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
            viewportHeight = $0
        }
        .background(colors.surface.standard.alternative)
        // Fade sits inside the clip so it doesn't square off the bottom corners.
        .overlay(alignment: .bottom) {
            if isOverflowing {
                LinearGradient(
                    colors: [
                        colors.surface.standard.alternative.opacity(0),
                        colors.surface.standard.alternative,
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: Spacing.n40)
                .allowsHitTesting(false)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
    }
}

private let contentPx = Sizing.PageLayout.ContentGrouping.Px.mobile
private let contentGap = Sizing.PageLayout.ContentGrouping.gap

// MARK: - Preview

private let previewLongDraft = """
Hi Jane,

Following up on our chat last week — I've booked the hiking trip for the \
weekend of the 12th. Can you confirm you're still in for the cabin?

Also, would you mind sharing your shoe size so I can sort out the rental \
crampons before we go?

Thanks,
Ford
"""

#Preview("Permission Sheets") {
    PermissionSheetGallery()
        .resolveTheme()
}

/// The four disclosure states, each opening the real ``appSheet`` so spacing,
/// detents and scrolling match production.
private struct PermissionSheetGallery: View {
    @Environment(\.colors) private var colors

    private enum Variant: String, CaseIterable, Identifiable {
        case noPhrases = "No phrases"
        case actionOnly = "Action phrase only"
        case inline = "Short disclosure — inline"
        case longInline = "Long inline — promotes to block"
        case block = "Long disclosure — scrollable"

        var id: String {
            rawValue
        }

        var toolDisplayName: String {
            switch self {
            case .noPhrases: "Calculator"
            case .actionOnly, .block: "Send Email"
            case .inline, .longInline: "Web Search"
            }
        }

        var disclosure: ToolDisclosure? {
            switch self {
            case .noPhrases:
                nil
            case .actionOnly:
                ToolDisclosure(actionPhrase: "draft an email")
            case .inline:
                ToolDisclosure(
                    actionPhrase: "search the web for",
                    detail: .inline("best hiking boots for big feet")
                )
            case .longInline:
                ToolDisclosure(
                    actionPhrase: "search the web for",
                    detail: .inline(
                        "waterproof insulated hiking boots for wide feet with " +
                            "good ankle support under 200 dollars available for " +
                            "next-day delivery near Copenhagen"
                    )
                )
            case .block:
                ToolDisclosure(
                    actionPhrase: "send an email to jane@doe.com",
                    detail: .block(previewLongDraft)
                )
            }
        }
    }

    @State private var presented: Variant?

    var body: some View {
        ZStack {
            colors.surface.standard.base.ignoresSafeArea()
            VStack(spacing: Sizing.PageLayout.ContentGrouping.gap) {
                ForEach(Variant.allCases) { variant in
                    AppSubtleActionButton(
                        variant.rawValue,
                        icon: Image(systemName: "hand.raised")
                    ) {
                        presented = variant
                    }
                }
            }
            .padding(.horizontal, contentPx)
        }
        .appSheet(
            isPresented: Binding(
                get: { presented != nil },
                set: { if !$0 { presented = nil } }
            ),
            title: Localized.Permission.sheetTitle,
            descriptionContent: presented.map { variant in
                AnyView(PermissionDisclosureText(
                    agentName: "Ford",
                    toolDisplayName: variant.toolDisplayName,
                    disclosure: variant.disclosure
                ))
            },
            fitsContent: true
        ) {
            if let variant = presented {
                PermissionRequestSheetContent(
                    agentName: "Ford",
                    toolDisplayName: variant.toolDisplayName,
                    disclosure: variant.disclosure,
                    allowOnceLabel: Localized.Permission.allowOnce,
                    allowForChatLabel: Localized.Permission.allowForChat,
                    denyLabel: Localized.Permission.deny
                ) { _ in presented = nil }
            }
        }
    }
}
