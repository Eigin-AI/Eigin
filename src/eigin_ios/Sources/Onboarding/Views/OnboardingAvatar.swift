import SwiftUI

/// The agent's presence throughout onboarding: a circular avatar that fills
/// organically as the agent comes together, then blooms from the Eigin mark
/// into the agent's own face.
///
/// Drive it with `progress` in 0...1. The fill is smoothed by ``ChasingProgress``
/// so it advances calmly rather than snapping between reported values. Provide
/// an `emoji` once the agent has chosen an identity to cross-fade the centre
/// from the brand mark to the agent's face.
///
/// Set `showsProgress` to `false` for the opening welcome moment: the avatar
/// lands at full power with no ring. Flipping it to `true` on the next step
/// fades the ring in and dims the mark to its progress level.
struct OnboardingAvatar: View {
    var progress: Double
    var emoji: String?
    var showsProgress: Bool
    /// Fades in on appear. Off when it should already be there, like at launch.
    var animatesIn: Bool
    var size: CGFloat

    init(
        progress: Double,
        emoji: String? = nil,
        showsProgress: Bool = true,
        animatesIn: Bool = true,
        size: CGFloat = 96
    ) {
        self.progress = progress
        self.emoji = emoji
        self.showsProgress = showsProgress
        self.animatesIn = animatesIn
        self.size = size
    }

    @Environment(\.colors) private var colors
    @State private var chaser = ChasingProgress()
    @State private var appeared = false

    private var fill: CGFloat {
        CGFloat(chaser.value)
    }

    private var ringWidth: CGFloat {
        max(3, size * 0.045)
    }

    /// The diameter of the green circle the mark or face sits in, inside the ring.
    private var vesselSize: CGFloat {
        size - ringWidth * 2.4
    }

    /// The brand mark's diameter, kept at the same proportion of its circle as
    /// ``AppBrandAvatar`` (an 8pt inset on its 56pt circle), measured against the
    /// green circle so the mark scales with it at every avatar size.
    private var brandMarkSize: CGFloat {
        vesselSize * (56 - Spacing.n8 * 2) / 56
    }

    private var ringOpacity: Double {
        showsProgress ? 1 : 0
    }

    private var markOpacity: Double {
        showsProgress ? 0.5 + 0.5 * Double(fill) : 1
    }

    private var markSaturation: Double {
        showsProgress ? 0.4 + 0.6 * Double(fill) : 1
    }

    var body: some View {
        ZStack {
            // Faint track the fill travels along.
            Circle()
                .stroke(colors.text.standard.muted.opacity(0.15), lineWidth: ringWidth)
                .frame(width: size, height: size)
                .opacity(ringOpacity)

            // The fill itself, in the brand green so it reads as Eigin coming
            // together.
            Circle()
                .trim(from: 0, to: fill)
                .stroke(
                    colors.surface.impact.base,
                    style: StrokeStyle(lineWidth: ringWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: size, height: size)
                .opacity(ringOpacity)

            // The face — dim while forming, full once the agent is whole.
            vessel
                .frame(width: vesselSize, height: vesselSize)
                .opacity(markOpacity)
                .saturation(markSaturation)
        }
        // A gentle fade-in, unless it is simply there from the start.
        .scaleEffect(appeared || !animatesIn ? 1 : 0.85)
        .opacity(appeared || !animatesIn ? 1 : 0)
        .animation(.easeOut(duration: 0.15), value: fill)
        .animation(.easeOut(duration: 0.5), value: showsProgress)
        .onAppear {
            chaser.setTarget(Float(progress))
            withAnimation(.spring(duration: 0.6, bounce: 0.2)) { appeared = true }
        }
        .onChange(of: progress) { _, new in chaser.setTarget(Float(new)) }
    }

    private var vessel: some View {
        ZStack {
            // The brand mark sits on the green spot; once the agent has a face,
            // the circle softens to a neutral secondary surface behind the emoji.
            Circle()
                .fill(emoji == nil ? colors.surface.impact.base : colors.surface.standard
                    .elevated)

            if let emoji {
                Text(emoji)
                    .font(.system(size: brandMarkSize * 0.85))
                    .id(emoji)
            } else {
                Iconography.Brand.avatar
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(colors.text.standard.base)
                    .frame(width: brandMarkSize, height: brandMarkSize)
            }
        }
        .clipShape(Circle())
        .animation(Animations.gentle, value: emoji)
    }
}

// MARK: - Preview

#Preview("Filling") {
    OnboardingAvatarPreview()
        .resolveTheme()
}

#Preview("Filling — Dark") {
    OnboardingAvatarPreview()
        .resolveTheme()
        .environment(\.colorScheme, .dark)
}

private struct OnboardingAvatarPreview: View {
    @Environment(\.colors) private var colors
    @State private var progress: Double = 0.0
    @State private var bloomed = false

    var body: some View {
        VStack(spacing: Spacing.n48) {
            OnboardingAvatar(progress: progress, emoji: bloomed ? "🔥" : nil, size: 120)

            VStack(spacing: Spacing.n16) {
                Slider(value: $progress, in: 0 ... 1)
                AppButton(bloomed ? "Reset" : "Bloom", variant: .secondary) {
                    bloomed.toggle()
                }
            }
            .padding(.horizontal, Spacing.n40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(colors.surface.standard.base.ignoresSafeArea())
    }
}
