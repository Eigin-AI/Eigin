import SwiftUI

/// Chat input with two visual states driven by focus.
///
/// Inactive: single-row pill with compact inline buttons on the right.
/// Active: text field expands into a card with a footer row for buttons.
struct AppChatInput: View {
    enum MicState { case idle, active, error }

    @Binding var text: String
    var placeholder: String = "Chat with Eigin"
    var isSendEnabled: Bool = false
    var showStopButton: Bool = false
    var micState: MicState = .idle
    var onSend: () -> Void
    var onStop: (() -> Void)?
    var onMicTap: () -> Void
    var onActionTap: (() -> Void)?

    var overlayText: String?
    var isFocused: FocusState<Bool>.Binding?
    @FocusState private var internalFocus: Bool
    @Environment(\.colors) private var colors

    private var focusBinding: FocusState<Bool>.Binding {
        isFocused ?? $internalFocus
    }

    // Visual states — driven from isFocused, each with its own animation speed.
    @State private var textActive = false
    @State private var boxExpanded = false
    @State private var showInline = true
    @State private var showFooter = false

    var body: some View {
        VStack(spacing: showFooter ? Spacing.n8 : 0) {
            HStack(spacing: Spacing.n16) {
                textFieldArea
                    .frame(maxWidth: .infinity)

                if showInline {
                    inlineButtons
                        .transition(.opacity)
                }
            }

            if showFooter {
                footerButtons
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(minHeight: Sizing.Button.Action.medium)
        .padding(.vertical, boxExpanded ? Spacing.n24 : Spacing.n8)
        .padding(.leading, boxExpanded ? Spacing.n32 : Sizing.Input.Px.left)
        .padding(.trailing, boxExpanded ? Spacing.n16 : Sizing.Input.Px.right)
        .background {
            let pillRadius: CGFloat = min(Radius.full, 100)
            UnevenRoundedRectangle(cornerRadii: RectangleCornerRadii(
                topLeading: boxExpanded ? Radius.card : pillRadius,
                bottomLeading: boxExpanded ? 0 : pillRadius,
                bottomTrailing: boxExpanded ? 0 : pillRadius,
                topTrailing: boxExpanded ? Radius.card : pillRadius
            ))
            .fill(colors.surface.standard.elevated)
        }
        .onTapGesture { focusBinding.wrappedValue = true }
        .padding(.horizontal, boxExpanded ? 0 : Spacing.n8)
        .frame(maxWidth: .infinity)
        .animation(Animations.snap, value: showFooter)
        .animation(Animations.smooth, value: boxExpanded)
        .animation(Animations.snap, value: textActive)
        .animation(Animations.smooth, value: showStopButton)
        .animation(Animations.snap, value: micState)
        .onChange(of: focusBinding.wrappedValue) { _, focused in
            textActive = focused
            boxExpanded = focused
            showInline = !focused
            showFooter = focused
        }
    }

    // MARK: - Text Field Area

    private var textFieldArea: some View {
        ZStack(alignment: .leading) {
            TextField(placeholder, text: $text, axis: .vertical)
                .typography(Typography.chatMessageUser)
                .foregroundStyle(colors.text.standard.base)
                .lineLimit(textActive ? 1 ... 10 : 1 ... 1)
                .focused(focusBinding)
                .opacity(textActive ? 1 : 0)
                .allowsHitTesting(textActive)

            if !textActive {
                let display = overlayText ?? text
                Text(display.isEmpty ? placeholder : display)
                    .typography(Typography.chatMessageUser)
                    .foregroundStyle(display.isEmpty
                        ? colors.text.standard.muted
                        : colors.text.standard.base)
                    .lineLimit(1)
                    .truncationMode(micState == .active ? .head : .tail)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Inline Buttons (inactive)

    private var inlineButtons: some View {
        HStack(spacing: Spacing.n16) {
            if onActionTap != nil {
                AppActionButton(
                    icon: Iconography.Functional.plus,
                    variant: .secondary,
                    size: .extraSmall,
                    action: { onActionTap?() }
                )
            }
            micButton(size: .extraSmall)
            sendOrStopButton(size: .medium)
        }
    }

    // MARK: - Footer Buttons (active)

    private var footerButtons: some View {
        HStack(spacing: Spacing.n16) {
            if onActionTap != nil {
                AppActionButton(
                    icon: Iconography.Functional.plus,
                    variant: .secondary,
                    size: .extraSmall,
                    action: { onActionTap?() }
                )
            }
            Spacer()
            micButton(size: .extraSmall)
            sendOrStopButton(size: .extraSmall)
        }
    }

    // MARK: - Shared Buttons

    private func micButton(size: AppButtonSize) -> some View {
        AppActionButton(
            icon: Iconography.Functional.microphone,
            variant: micState == .active ? .spot : .secondary,
            size: size,
            action: onMicTap
        )
        .pulse(isActive: micState == .active)
    }

    private func sendOrStopButton(size: AppButtonSize) -> some View {
        AppActionButton(
            icon: showStopButton ? Iconography.Brand.pause : Iconography.Functional.Arrow.up,
            variant: .primary,
            size: size,
            action: showStopButton ? (onStop ?? {}) : onSend
        )
        .disabled(!showStopButton && !isSendEnabled)
        // Stable anchor for UI tests of send-driven flows.
        .accessibilityIdentifier("chat-send")
    }
}

// MARK: - Preview

#Preview("States") {
    AppChatInputStatesPreview()
        .resolveTheme()
}

#Preview("Interaction") {
    AppChatInputInteractionPreview()
        .resolveTheme()
}

private struct AppChatInputStatesPreview: View {
    @State private var text = ""
    @State private var filledText = "Hmm, I'm not sure. I don't know, what do you think?"
    @Environment(\.colors) private var colors

    var body: some View {
        VStack(spacing: Spacing.n24) {
            AppChatInput(
                text: $text,
                isSendEnabled: false,
                onSend: {},
                onMicTap: {},
                onActionTap: {}
            )
            AppChatInput(
                text: $filledText,
                isSendEnabled: true,
                onSend: {},
                onMicTap: {},
                onActionTap: {}
            )
            AppChatInput(
                text: $text,
                micState: .active,
                onSend: {},
                onMicTap: {},
                onActionTap: {}
            )
        }
        .padding(.vertical, Spacing.n24)
        .background(colors.surface.standard.base)
    }
}

/// Full-screen layout matching the chat screen — tap the background to dismiss keyboard.
private struct AppChatInputInteractionPreview: View {
    @State private var text = ""
    @State private var micState: AppChatInput.MicState = .idle
    @Environment(\.colors) private var colors

    var body: some View {
        ZStack(alignment: .bottom) {
            colors.surface.standard.base.ignoresSafeArea()
                .onTapGesture {
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder),
                        to: nil, from: nil, for: nil
                    )
                }

            VStack(spacing: 0) {
                Spacer()
                AppChatInput(
                    text: $text,
                    isSendEnabled: !text.trimmingCharacters(in: .whitespaces).isEmpty,
                    micState: micState,
                    onSend: { text = "" },
                    onMicTap: { micState = micState == .active ? .idle : .active },
                    onActionTap: {}
                )
                .padding(.bottom, Spacing.n8)
            }
        }
    }
}
