import SwiftUI

/// Shared chrome for the onboarding setup screens, giving every screen the same
/// rhythm: the persistent ``OnboardingAvatar`` at the top, the agent's spoken
/// line typed directly beneath it, then the screen's interactive content.
///
/// The coordinator wraps this once around the changing screens so the avatar
/// instance — and its fill — stays continuous, and so each new line reads as the
/// same presence speaking.
struct OnboardingScaffold<Content: View>: View {
    let progress: Double
    var emoji: String?
    var showsProgress: Bool
    var entrance: Bool
    let title: String
    let text: String
    var titleDelay: Duration
    @ViewBuilder var content: () -> Content

    @Environment(\.colors) private var colors
    @State private var spokenText = ""
    /// Whether the opening avatar has settled from its big, centered entrance up
    /// to its place at the top. Starts already settled on every screen but the
    /// welcome moment.
    @State private var landed: Bool

    /// Whether the line currently on screen has finished being spoken.
    private var revealed: Bool {
        spokenText == text
    }

    init(
        progress: Double,
        emoji: String? = nil,
        showsProgress: Bool = true,
        entrance: Bool = false,
        title: String,
        text: String,
        titleDelay: Duration = .zero,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.progress = progress
        self.emoji = emoji
        self.showsProgress = showsProgress
        self.entrance = entrance
        self.title = title
        self.text = text
        self.titleDelay = titleDelay
        self.content = content
        _landed = State(initialValue: !entrance)
    }

    var body: some View {
        VStack(spacing: Spacing.n24) {
            OnboardingAvatar(
                progress: progress,
                emoji: emoji,
                showsProgress: showsProgress
            )
            // Big and centered while landing (the only child, so the stack
            // centers it), then settling to its normal size at the top once the
            // speech and content come in.
            .scaleEffect(landed ? 1 : 1.5)
            .padding(.top, Spacing.n32)

            // Held back until the avatar has landed, so it can hold the screen on
            // its own first. Adding the expanding content lifts the avatar to the
            // top.
            if landed {
                OnboardingSpeech(
                    title: title,
                    text: text,
                    finished: $spokenText,
                    titleDelay: titleDelay
                )
                .transition(.opacity)

                // Standardized entrance: the screen's content appears only once
                // the agent has finished speaking *this* line. Comparing against
                // the current text hides content the instant the line changes,
                // with no lag.
                content()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(revealed ? 1 : 0)
                    .offset(y: revealed ? 0 : 8)
                    .allowsHitTesting(revealed)
                    .animation(.easeOut(duration: Animations.normal), value: revealed)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, Spacing.n24)
        .padding(.bottom, Spacing.n32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(colors.surface.standard.base.ignoresSafeArea())
        .task { await landAvatar() }
    }

    /// On the welcome moment, lets the avatar hold the centre of the screen for a
    /// beat before settling to the top and revealing the rest.
    private func landAvatar() async {
        guard !landed else { return }
        try? await Task.sleep(for: .milliseconds(1500))
        withAnimation(.spring(duration: Animations.slow, bounce: 0.2)) { landed = true }
    }
}

// MARK: - Preview

#Preview {
    OnboardingScaffold(
        progress: 0.2,
        title: "Nice to meet you.",
        text: "First, what should I call you?"
    ) {
        VStack {
            Spacer()
            AppButton("Continue") {}
        }
    }
    .resolveTheme()
}
