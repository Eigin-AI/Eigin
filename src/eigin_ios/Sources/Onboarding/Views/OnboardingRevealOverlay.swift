import SwiftUI

/// The hero reveal, played full-bleed over the chat surface when onboarding
/// finishes. It mirrors the setup screens' layout — avatar, headline, streamed
/// line — so the moment reads as the same presence. The avatar blooms from the
/// Eigin mark into the agent's own face, then the agent names itself and speaks
/// a digest of its constitution. Tapping through continues into the app.
struct OnboardingRevealOverlay: View {
    let agent: Agent
    let digest: String
    let onContinue: () -> Void

    @Environment(\.colors) private var colors

    @State private var bloomed = false
    @State private var spokenText = ""
    @State private var continued = false

    /// Whether the agent has finished introducing itself.
    private var revealed: Bool {
        spokenText == digest
    }

    var body: some View {
        VStack(spacing: Spacing.n24) {
            // No ring here — just the bloom from the mark into the agent's face.
            OnboardingAvatar(
                progress: 0,
                emoji: bloomed ? agent.emoji : nil,
                showsProgress: false,
                size: 140
            )
            .padding(.top, Spacing.n32)

            OnboardingSpeech(
                title: Localized.Onboarding.Reveal.title(agent.name),
                text: digest,
                finished: $spokenText,
                // Hold on the mark, bloom, then speak — see `run()`.
                titleDelay: .milliseconds(2500)
            )

            // Continue, revealed once the agent has finished speaking, matching
            // the setup screens' content entrance.
            VStack {
                Spacer()
                AppButton(Localized.Common.Actions.continue) {
                    guard !continued else { return }
                    continued = true
                    onContinue()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(revealed ? 1 : 0)
            .offset(y: revealed ? 0 : 8)
            .allowsHitTesting(revealed)
            .animation(.easeOut(duration: Animations.slow), value: revealed)
        }
        .padding(.horizontal, Spacing.n24)
        .padding(.bottom, Spacing.n32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(colors.surface.standard.base.ignoresSafeArea())
        .task { await run() }
    }

    private func run() async {
        // The Eigin mark lands and holds for about a second, then blooms into the
        // agent's face just before the headline (delayed to match) appears.
        try? await Task.sleep(for: .milliseconds(1500))
        withAnimation(Animations.gentle) { bloomed = true }
    }
}

#Preview {
    let agent = Agent(name: "Ford", providerID: UUID(), model: "test")
    agent.emoji = "🛰️"
    return OnboardingRevealOverlay(
        agent: agent,
        digest: "I'm here to help you think clearly and build with total privacy. "
            + "Everything we do stays yours.",
        onContinue: {}
    )
    .resolveTheme()
}
