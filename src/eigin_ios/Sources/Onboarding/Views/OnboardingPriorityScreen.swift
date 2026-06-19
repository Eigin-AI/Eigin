import SwiftUI

/// Asks what the user values most, as a swipeable carousel of visual cards.
/// The focused card is centered and full-size; neighbors peek in, scaled down.
/// Tapping a card selects it. The prompt is spoken by the avatar via the
/// scaffold.
struct OnboardingPriorityScreen: View {
    let onSelect: (OnboardingPriority) -> Void

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            PriorityCarousel(onSelect: onSelect)
            Spacer(minLength: 0)
        }
    }
}

private struct PriorityCarousel: View {
    let onSelect: (OnboardingPriority) -> Void

    private let cardWidth: CGFloat = 300

    var body: some View {
        GeometryReader { geometry in
            let sideInset = max(0, (geometry.size.width - cardWidth) / 2)

            ScrollView(.horizontal) {
                HStack(spacing: Spacing.n16) {
                    ForEach(OnboardingPriority.allCases) { priority in
                        AppVisualCard(
                            priority.title,
                            explainer: priority.explainer,
                            symbol: priority.illustration,
                            variant: variant(for: priority)
                        ) {
                            onSelect(priority)
                        }
                        .scrollTransition(.interactive) { content, phase in
                            content
                                .scaleEffect(phase.isIdentity ? 1 : 0.88)
                                .opacity(phase.isIdentity ? 1 : 0.55)
                        }
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .contentMargins(.horizontal, sideInset, for: .scrollContent)
            .scrollIndicators(.hidden)
        }
        .frame(height: 380)
        // Bleed past the scaffold's horizontal padding so neighboring cards peek
        // in from the screen edges.
        .padding(.horizontal, -Spacing.n24)
    }

    private func variant(for priority: OnboardingPriority) -> AppVisualCardVariant {
        switch priority {
        case .stayOnTop: .brand
        case .people: .warm
        case .clarity: .soft
        case .somethingElse: .neutral
        }
    }
}

#Preview {
    OnboardingScaffold(
        progress: 0.2,
        title: "Nice to meet you, Alex.",
        text: """
        What are you hoping to do with your personal AI?

        I can shape myself around that.
        """
    ) {
        OnboardingPriorityScreen(onSelect: { _ in })
    }
    .resolveTheme()
}
