import SwiftUI

/// Shared chrome for the onboarding setup screens, giving every screen the same
/// rhythm: the persistent ``OnboardingAvatar`` at the top, the agent's spoken
/// line typed directly beneath it, then the screen's interactive content.
///
/// The coordinator wraps this once around the changing screens so the avatar
/// instance — and its fill — stays continuous, and so each new line reads as the
/// same presence speaking. Each screen's line and content form an
/// ``OnboardingTurn``: a new `turnID` fades the old turn out over the new one,
/// which is already laid out and waiting to speak.
///
/// With `entrance`, the avatar opens where the launch screen left the mark —
/// centered at ``LaunchMark/diameter`` — then plays ``OpeningTimeline``: it
/// works up the energy to jump and bounces up to its place. The layout is
/// final from the first frame; only the avatar moves.
///
/// When a screen is too short for it all, as in landscape, the whole screen
/// scrolls, avatar and line included, so the content stays reachable.
struct OnboardingScaffold<Content: View>: View {
    let progress: Double
    var emoji: String?
    var showsProgress: Bool
    var entrance: Bool
    /// Identifies the current screen. A new value plays the screen change.
    var turnID: String
    let title: String
    let text: String
    var titleDelay: Duration
    @ViewBuilder var content: () -> Content

    @Environment(\.colors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// When the opening started playing; nil holds it on its first frame.
    @State private var openedAt: Date?
    /// The opening is over, or never played: the avatar sits in its slot.
    @State private var settled: Bool
    @State private var avatarOpacity: Double = 1
    /// Centers in global space of the avatar's slot and of the full screen.
    @State private var slotCenter: CGPoint?
    @State private var screenCenter: CGPoint?

    private static var avatarSize: CGFloat {
        96
    }

    init(
        progress: Double,
        emoji: String? = nil,
        showsProgress: Bool = true,
        entrance: Bool = false,
        turnID: String = "",
        title: String,
        text: String,
        titleDelay: Duration = .zero,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.progress = progress
        self.emoji = emoji
        self.showsProgress = showsProgress
        self.entrance = entrance
        self.turnID = turnID
        self.title = title
        self.text = text
        self.titleDelay = titleDelay
        self.content = content
        _settled = State(initialValue: !entrance)
    }

    /// The avatar's scale at which its circle matches the launch screen's mark.
    private static var launchScale: CGFloat {
        LaunchMark.diameter / OnboardingAvatar.vesselSize(for: avatarSize)
    }

    /// Where the avatar is at `date`.
    private func pose(at date: Date) -> OpeningTimeline.Pose {
        if settled { return .settled }
        let t = openedAt.map { date.timeIntervalSince($0) } ?? 0
        return OpeningTimeline.pose(at: t, launchScale: Self.launchScale)
    }

    /// From screen center to the slot, scaled by how far the avatar has risen.
    private func travel(_ rise: Double) -> CGSize {
        guard let slotCenter, let screenCenter else { return .zero }
        return CGSize(
            width: (slotCenter.x - screenCenter.x) * rise,
            height: (slotCenter.y - screenCenter.y) * rise
        )
    }

    /// Off center, the avatar can't be placed until both centers are known.
    private var placed: Bool {
        slotCenter != nil && screenCenter != nil
    }

    var body: some View {
        GeometryReader { viewport in
            ScrollView {
                VStack(spacing: Spacing.n24) {
                    // Holds the avatar's place in the layout; the avatar renders
                    // in the overlay above, following the slot as it scrolls.
                    Color.clear
                        .frame(width: Self.avatarSize, height: Self.avatarSize)
                        .onGeometryChange(for: CGPoint.self) { proxy in
                            let frame = proxy.frame(in: .global)
                            return CGPoint(x: frame.midX, y: frame.midY)
                        } action: { slotCenter = $0 }
                        .padding(.top, Spacing.n32)

                    // Overlay: during a screen change the outgoing and incoming
                    // turns coexist for one fade without moving anything.
                    ZStack {
                        OnboardingTurn(
                            title: title,
                            text: text,
                            titleDelay: titleDelay,
                            content: content()
                        )
                        .id(turnID)
                        .transition(.asymmetric(insertion: .identity, removal: .opacity))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .animation(.easeOut(duration: OnboardingTiming.turnFade), value: turnID)
                }
                .padding(.horizontal, Spacing.n24)
                .padding(.bottom, Spacing.n32)
                // Short screens still fill the viewport, keeping content at the bottom.
                .frame(maxWidth: .infinity, minHeight: viewport.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
            // No header floats here; the soft edge softens content into the bare screen.
            .softEdge()
            .scrollIndicators(.hidden)
        }
        .background(colors.surface.standard.base.ignoresSafeArea())
        .overlay { avatarLayer.ignoresSafeArea() }
        .task { await playOpening() }
    }

    /// The avatar, centered on the full screen like the launch screen's mark,
    /// and offset up into its slot as it rises.
    private var avatarLayer: some View {
        TimelineView(.animation(paused: settled || openedAt == nil)) { context in
            let pose = pose(at: context.date)
            OnboardingAvatar(
                progress: progress,
                emoji: emoji,
                showsProgress: showsProgress,
                animatesIn: !entrance,
                breath: pose.breath,
                stretch: pose.stretch
            )
            .scaleEffect(pose.scale)
            .offset(travel(pose.rise))
            .opacity(pose.rise == 0 || placed ? avatarOpacity : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: CGPoint.self) { proxy in
            let frame = proxy.frame(in: .global)
            return CGPoint(x: frame.midX, y: frame.midY)
        } action: { screenCenter = $0 }
        .allowsHitTesting(false)
    }

    /// Plays the opening on the timeline's clock, then settles for good so
    /// the clock stops. Reduce Motion cross-fades the mark to its slot instead.
    private func playOpening() async {
        guard !settled else { return }

        if reduceMotion {
            try? await Task.sleep(for: .seconds(OpeningTimeline.hold))
            withAnimation(.easeOut(duration: Animations.normal)) { avatarOpacity = 0 }
            try? await Task.sleep(for: .seconds(Animations.normal))
            settled = true
            withAnimation(.easeIn(duration: Animations.slow)) { avatarOpacity = 1 }
            return
        }

        openedAt = .now
        try? await Task.sleep(for: .seconds(OpeningTimeline.opened))
        settled = true
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
