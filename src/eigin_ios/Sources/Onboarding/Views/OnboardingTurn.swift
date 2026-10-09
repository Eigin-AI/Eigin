import SwiftUI

/// One screen's worth of the agent speaking: its line, then the screen's
/// interactive content once the line has landed.
///
/// The scaffold gives each turn its own identity, so every screen starts from a
/// clean, fully laid-out but invisible state, and the outgoing turn keeps its
/// layout while it fades.
struct OnboardingTurn<Content: View>: View {
    let title: String
    let text: String
    var titleDelay: Duration
    /// The screen's interactive content, shown once the line has landed.
    let content: Content

    /// Set to `text` once the line has finished being spoken.
    @State private var spokenText = ""

    private var revealed: Bool {
        spokenText == text
    }

    var body: some View {
        VStack(spacing: Spacing.n24) {
            OnboardingSpeech(
                title: title,
                text: text,
                finished: $spokenText,
                titleDelay: titleDelay
            )

            // The content area scrolls when a screen is taller than the space
            // left under the speech — the line stays put. Short content still
            // fills the viewport, keeping the Spacer-centered layouts.
            GeometryReader { viewport in
                ScrollView {
                    content
                        // The scroll area itself runs edge to edge so wide
                        // content (the priority carousel's peeking cards) isn't
                        // clipped at the padding line.
                        .padding(.horizontal, Spacing.n24)
                        .frame(maxWidth: .infinity, minHeight: viewport.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.hidden)
            }
            .opacity(revealed ? 1 : 0)
            .offset(y: revealed ? 0 : 8)
            .allowsHitTesting(revealed)
            // The scroll view escapes the scaffold's horizontal padding; its
            // content pads itself instead.
            .padding(.horizontal, -Spacing.n24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
