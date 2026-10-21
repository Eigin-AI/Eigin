import SwiftUI

/// The hero reveal, played full-bleed over the chat when onboarding commits. The
/// hatch plays out alone in the middle of the screen; once the face has landed
/// it rises to the top, as the welcome avatar does, and only then does the
/// agent name itself and say what it is for. Tapping through continues into
/// the app.
struct OnboardingRevealOverlay: View {
    let agent: Agent
    /// The agent's own line about itself, from its commit.
    let digest: String
    let onContinue: () -> Void

    @Environment(\.colors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var landed = false
    @State private var spokenText = ""
    @State private var continued = false

    private static let hatchSize: CGFloat = 140

    /// Whether the agent has finished introducing itself.
    private var revealed: Bool {
        spokenText == digest
    }

    var body: some View {
        GeometryReader { viewport in
            ScrollView {
                VStack(spacing: Spacing.n24) {
                    // While it hatches it is the only thing on screen and takes all of
                    // it, so it sits centred; once landed it shrinks to its own size at
                    // the top and the rest comes in under it.
                    AgentHatch(emoji: agent.emoji, size: Self.hatchSize)
                        .frame(maxHeight: landed ? nil : .infinity)

                    if landed {
                        // The name once it has risen, then a longer beat before the line.
                        OnboardingSpeech(
                            title: Localized.Onboarding.Reveal.title(agent.name),
                            text: digest,
                            finished: $spokenText,
                            // Reduced motion: no waiting beats, the line is just there.
                            titleDelay: reduceMotion ? .zero : .milliseconds(500),
                            streamDelay: reduceMotion ? .zero : .milliseconds(1100)
                        )

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
                }
                // Sides use the screen gutter. Top and bottom are even, so the
                // hatch (sized against this frame) centres on the screen.
                .padding(.horizontal, Spacing.n24)
                .padding(.vertical, Spacing.n32)
                // Fills the screen; on a short one, as in landscape, it scrolls
                // so Continue stays reachable.
                .frame(maxWidth: .infinity, minHeight: viewport.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
            // No header floats here; the soft edge softens content into the bare screen.
            .softEdge()
            .scrollIndicators(.hidden)
            // The hatch plays out alone, held still; only then can a short screen scroll.
            .scrollDisabled(!landed)
            // The burst spills past the hatch, unclipped: the screen edge is where it stops.
            .scrollClipDisabled()
        }
        // The keyboard may still be up from the last message; the reveal ignores it.
        .ignoresSafeArea(.keyboard)
        .background(colors.surface.standard.base.ignoresSafeArea())
        .task {
            guard !reduceMotion else {
                // Reduced motion: the hatch is settled as drawn, so skip
                // straight to the speech. The hatch itself pauses immediately.
                landed = true
                return
            }
            try? await Task.sleep(for: .seconds(HatchTimeline.lands))
            // The same settle the welcome avatar makes on its way up.
            withAnimation(.spring(duration: 0.4, bounce: 0.2)) { landed = true }
        }
    }
}

#Preview {
    let agent = Agent(name: "Ford", providerID: UUID(), model: "test")
    agent.emoji = "🛰️"
    return OnboardingRevealOverlay(
        agent: agent,
        digest: "I'm here to keep your days in order without making a fuss about it.\n\nA short rundown each morning, and a nudge before things slip.",
        onContinue: {}
    )
    .resolveTheme()
}
