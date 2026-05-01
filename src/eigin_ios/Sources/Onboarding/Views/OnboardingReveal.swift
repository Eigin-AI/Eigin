import SwiftUI

/// The hero reveal screen shown after onboarding completes.
///
/// Displays the agent's name with a spring animation, reveals the hero
/// paragraph with a curtain-like fade, then fades in a tailored cloud-AI
/// pitch and action buttons.
struct OnboardingReveal: View {
    @Environment(\.colors) private var colors

    let agent: Agent
    let heroText: String
    let priority: OnboardingPriority?
    let showUpgradePitch: Bool
    let onConnectCloud: () -> Void
    let onStayLocal: () -> Void

    // Animation phases:
    // 0: blank, 1: name springs in, 2: paragraph reveals,
    // 3: pitch block fades in, 4: buttons fade in
    @State private var phase = 0
    @State private var curtainProgress: CGFloat = 0

    private var nameLine: String {
        let name = agent.name
        let emoji = agent.emoji
        return Localized.Agent.identityStatement("\(name) \(emoji)")
    }

    private var subHeader: String {
        switch priority {
        case .privacy:
            Localized.Onboarding.Features.Security.description
        case .power:
            Localized.Onboarding.Provider.giveBrainPower(agent.name)
        case .speed:
            Localized.Onboarding.Provider.keepMovingFast(agent.name)
        case .freedom:
            Localized.Onboarding.Features.Choice.description
        case nil:
            Localized.Onboarding.Complete.title
        }
    }

    private var bodyText: String {
        let name = agent.name
        switch priority {
        case .privacy:
            return Localized.Onboarding.Chat.localExplanation(name)
        case .power:
            return Localized.Onboarding.Chat.powerExplanation(name)
        case .speed:
            return Localized.Onboarding.Provider.speedExplanation(name)
        case .freedom:
            return Localized.Onboarding.Chat.choiceExplanation
        case nil:
            return Localized.Onboarding.Chat.upgradePrompt(name)
        }
    }

    var body: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()

            // Name line — springs in
            Text(nameLine)
                .font(Typography.largeTitle)
                .foregroundStyle(colors.textPrimary)
                .opacity(phase >= 1 ? 1 : 0)
                .scaleEffect(phase >= 1 ? 1 : 0.8)
                .animation(.spring(duration: 0.7, bounce: 0.15), value: phase >= 1)

            // Hero paragraph — curtain reveal from top with gradient mask
            Text(heroText)
                .font(Typography.headline)
                .foregroundStyle(colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.lg)
                .frame(maxWidth: 500)
                .mask(
                    GradientCurtainMask(progress: curtainProgress)
                )
                .opacity(phase >= 2 ? 1 : 0)

            Spacer()

            // Pitch block — left-aligned like OnboardingWelcome values
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text(subHeader)
                    .font(Typography.headline)
                    .foregroundStyle(colors.textPrimary)

                Text(bodyText)
                    .font(Typography.body)
                    .foregroundStyle(colors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.lg)
            .opacity(showUpgradePitch && phase >= 3 ? 1 : 0)
            .offset(y: showUpgradePitch && phase >= 3 ? 0 : 12)
            .animation(.easeOut(duration: 0.6), value: phase >= 3)

            // Action buttons
            VStack(spacing: Spacing.md) {
                if showUpgradePitch {
                    Button {
                        onConnectCloud()
                    } label: {
                        Text(Localized.Onboarding.Provider.connectAction)
                            .font(Typography.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(colors.accent)

                    Button {
                        onStayLocal()
                    } label: {
                        Text(Localized.Onboarding.Provider.localAction)
                            .font(Typography.callout)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(colors.textSecondary)
                } else {
                    Button {
                        onStayLocal()
                    } label: {
                        Text(Localized.Onboarding.Welcome.primaryAction)
                            .font(Typography.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(colors.accent)
                }
            }
            .opacity(phase >= 4 ? 1 : 0)
            .offset(y: phase >= 4 ? 0 : 12)
            .animation(.easeOut(duration: 0.6), value: phase >= 4)
            .padding(.horizontal, Spacing.lg)
            .padding(.bottom, Spacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(colors.background.ignoresSafeArea())
        .task {
            await runAnimation()
        }
    }

    // MARK: - Animation Sequence

    private func runAnimation() async {
        // Phase 1: Name springs in
        try? await Task.sleep(for: .milliseconds(500))
        withAnimation(.spring(duration: 0.7, bounce: 0.15)) {
            phase = 1
        }

        // Phase 2: Hero paragraph curtain reveal
        try? await Task.sleep(for: .milliseconds(1000))
        withAnimation(.easeOut(duration: 0.2)) {
            phase = 2
        }
        withAnimation(.easeOut(duration: 1)) {
            curtainProgress = 1
        }

        // Phase 3: Pitch block fades in
        try? await Task.sleep(for: .milliseconds(2000))
        withAnimation(.easeOut(duration: 0.6)) {
            phase = 3
        }

        // Phase 4: Buttons fade in
        try? await Task.sleep(for: .milliseconds(500))
        withAnimation(.easeOut(duration: 0.6)) {
            phase = 4
        }
    }
}

/// A mask that reveals content from top to bottom with a soft gradient edge.
/// White = visible, black = hidden.
private struct GradientCurtainMask: View {
    var progress: CGFloat

    var body: some View {
        GeometryReader { geometry in
            let height = geometry.size.height
            let revealY = height * (1 - progress)

            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: .white, location: 0),
                    .init(color: .white, location: max(0, revealY / height - 0.15)),
                    .init(color: .black, location: revealY / height),
                    .init(color: .black, location: 1),
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

#Preview {
    let agent = Agent(name: "Nova", providerID: UUID(), model: "gemma-4-e2b")
    agent.emoji = "🦉"

    return OnboardingReveal(
        agent: agent,
        heroText: "I'm here to help you learn how to code and bring order to daily life.",
        priority: .power,
        showUpgradePitch: true,
        onConnectCloud: {},
        onStayLocal: {}
    )
    .previewEnvironment()
}
