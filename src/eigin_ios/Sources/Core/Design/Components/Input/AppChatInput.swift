import SwiftUI

struct AppChatInput: View {
    enum MicState { case idle, active, error }

    @Binding var text: String
    var placeholder: String = "Chat with Eigin"
    var isSendEnabled: Bool = false
    var micState: MicState = .idle
    var onSend: () -> Void
    var onMicTap: () -> Void

    @FocusState private var isFocused: Bool
    @Environment(\.colors) private var colors
    /// Single state drives all visual changes through one withAnimation context.
    @State private var isActive = false

    var body: some View {
        HStack(spacing: isActive ? Spacing.n16 : Spacing.n8) {
            ZStack(alignment: .leading) {
                TextField(placeholder, text: $text, axis: .vertical)
                    .typography(Typography.chatMessageUser)
                    .foregroundStyle(colors.text.standard.base)
                    .lineLimit(isActive ? 1 ... 10 : 1 ... 1)
                    .focused($isFocused)
                    .opacity(isActive ? 1 : 0)
                    .allowsHitTesting(isActive)

                if !isActive {
                    Text(text.isEmpty ? placeholder : text)
                        .typography(Typography.chatMessageUser)
                        .foregroundStyle(text.isEmpty
                            ? colors.text.standard.muted
                            : colors.text.standard.base)
                        .lineLimit(1)
                        .truncationMode(micState == .active ? .head : .tail)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                        .id(micState)
                }
            }
            .frame(maxWidth: .infinity)

            AppActionButton(
                icon: Image(systemName: micState == .active ? "mic.fill" : "mic"),
                variant: micState == .active ? .spot : .open,
                size: isActive ? .small : .medium,
                action: onMicTap
            )
            .pulse(isActive: micState == .active)
            .animation(Animations.smooth, value: micState)

            AppActionButton(
                icon: Image(systemName: "arrow.up"),
                variant: .primary,
                size: isActive ? .small : .medium,
                action: onSend
            )
            .disabled(!isSendEnabled)
        }
        .padding(.vertical, isActive ? Spacing.n24 : Spacing.n8)
        .padding(.leading, isActive ? Spacing.n32 : Sizing.Input.Px.left)
        .padding(.trailing, isActive ? Spacing.n16 : Sizing.Input.Px.right)
        .background {
            // Very large radii breaks animations for uneven rectangles
            // We clamp it to a maximum of 100 so the animation works
            let pillRadius: CGFloat = min(Radius.full, 100)
            UnevenRoundedRectangle(cornerRadii: RectangleCornerRadii(
                topLeading: isActive ? Radius.card : pillRadius,
                bottomLeading: isActive ? 0 : pillRadius,
                bottomTrailing: isActive ? 0 : pillRadius,
                topTrailing: isActive ? Radius.card : pillRadius
            ))
            .fill(colors.surface.standard.elevated)
        }
        .onTapGesture { isFocused = true }
        .padding(.horizontal, isActive ? 0 : Spacing.n8)
        .frame(maxWidth: .infinity)
        .animation(Animations.smooth, value: text)
        .animation(Animations.smooth, value: micState)
        .onChange(of: isFocused) { _, focused in
            withAnimation(Animations.smooth) {
                isActive = focused
            }
        }
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
            AppChatInput(text: $text, isSendEnabled: false, onSend: {}, onMicTap: {})
            AppChatInput(text: $filledText, isSendEnabled: true, onSend: {}, onMicTap: {})
            AppChatInput(text: $text, micState: .active, onSend: {}, onMicTap: {})
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
                    onMicTap: { micState = micState == .active ? .idle : .active }
                )
                .padding(.bottom, Spacing.n8)
            }
        }
    }
}
