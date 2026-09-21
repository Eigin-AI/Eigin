import SwiftUI

/// Asks what the user values most, as a swipeable carousel of visual cards.
/// The focused card is centered and full-size; neighbors peek in, scaled down.
/// Tapping a card selects it. The prompt is spoken by the avatar via the
/// scaffold.
struct OnboardingPriorityScreen: View {
    let onSelect: (OnboardingPriority) -> Void

    var body: some View {
        // The carousel's GeometryReader owns the whole content area and centers
        // its carousel block inside it, so the block always fits the viewport.
        PriorityCarousel(onSelect: onSelect)
    }
}

private struct PriorityCarousel: View {
    let onSelect: (OnboardingPriority) -> Void

    var body: some View {
        GeometryReader { geometry in
            // Design size when there's at least 360pt of carousel height — the
            // card's design height. Under that the cards go compact (the same
            // boundary AppVisualCard applies to cardHeight) and take the full
            // viewport height; they also narrow, so neighboring cards stay
            // visible at the screen edges (iPhone SE, iPad compatibility mode).
            let carouselHeight = min(380, geometry.size.height)
            let isCompact = carouselHeight < 360
            let cardHeight = isCompact ? carouselHeight : 360
            let cardWidth: CGFloat = isCompact
                ? min(300, geometry.size.width - 150)
                : 300
            let sideInset = max(0, (geometry.size.width - cardWidth) / 2)

            ScrollView(.horizontal) {
                HStack(spacing: Spacing.n16) {
                    ForEach(OnboardingPriority.allCases) { priority in
                        AppVisualCard(
                            priority.title,
                            explainer: priority.explainer,
                            symbol: priority.illustration,
                            variant: variant(for: priority),
                            width: cardWidth,
                            height: cardHeight
                        ) {
                            onSelect(priority)
                        }
                        .scrollTransition(.interactive) { content, phase in
                            // Scale outward from the peeking edge, so the
                            // sliver that reaches the screen edge stays full
                            // size — a center anchor pulls it offscreen.
                            content
                                .scaleEffect(
                                    phase.isIdentity ? 1 : 0.96,
                                    anchor: phase.value < 0 ? .trailing : .leading
                                )
                                .opacity(phase.isIdentity ? 1 : 0.7)
                        }
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .contentMargins(.horizontal, sideInset, for: .scrollContent)
            .scrollIndicators(.hidden)
            .frame(height: carouselHeight)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
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
