import SwiftUI

struct OnboardingWelcome: View {
    @Environment(\.colors) private var colors

    let onGetStarted: () -> Void

    // Animation phases
    @State private var phase = 0 // 0: blank, 1: hello, 2: meet eigin, 3: full
    @State private var meetEiginText = ""
    @State private var currentVerbIndex = 0

    private let meetEiginFull = Localized.Onboarding.Welcome.hero

    private let cyclingVerbs = [
        Localized.Onboarding.Welcome.Words.think,
        Localized.Onboarding.Welcome.Words.write,
        Localized.Onboarding.Welcome.Words.plan,
        Localized.Onboarding.Welcome.Words.remember,
        Localized.Onboarding.Welcome.Words.create,
        Localized.Onboarding.Welcome.Words.organise,
    ]

    var body: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()

            // Hero area — hello fades out, meet eigin fades in
            ZStack {
                // Phase 1: "Hello 👋"
                HStack(spacing: Spacing.sm) {
                    Text(Localized.Onboarding.Welcome.greeting)
                        .typography(Typography.largeTitle)
                    Text(Localized.Onboarding.Welcome.emoji)
                        .font(.system(size: 36))
                }
                .foregroundStyle(colors.textPrimary)
                .opacity(phase == 1 ? 1 : 0)
                .scaleEffect(phase >= 1 ? 1 : 0.8)

                // Phase 2+: "Meet Eigin" + tagline
                Text(meetEiginText)
                    .typography(Typography.largeTitle)
                    .foregroundStyle(colors.textPrimary)
                    .opacity(phase >= 2 ? 1 : 0)
            }

            Spacer()

            // Values
            VStack(alignment: .leading, spacing: Spacing.lg) {
                Text(Localized.Onboarding.Welcome.subtitle)
                    .typography(Typography.headline)
                    .foregroundStyle(colors.textSecondary)

                valueRow(icon: "sparkles", title: {
                    HStack(spacing: 0) {
                        Text(Localized.Onboarding.Welcome.verbPrefix)
                        Text(cyclingVerbs[currentVerbIndex])
                            .contentTransition(.numericText())
                    }
                }, subtitle: Localized.Onboarding.Features.Power.tagline)

                valueRow(
                    icon: "person.fill",
                    title: { Text(Localized.Onboarding.Features.Privacy.title) },
                    subtitle: Localized.Onboarding.Features.Privacy.description
                )

                valueRow(
                    icon: "lock.fill",
                    title: { Text(Localized.Onboarding.Features.Security.title) },
                    subtitle: Localized.Onboarding.Features.Privacy.storage
                )

                valueRow(
                    icon: "arrow.triangle.swap",
                    title: { Text(Localized.Onboarding.Features.Choice.title) },
                    subtitle: Localized.Onboarding.Features.Choice.tagline
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(phase >= 3 ? 1 : 0)
            .offset(y: phase >= 3 ? 0 : 12)

            // Actions
            Button {
                onGetStarted()
            } label: {
                Text(Localized.Onboarding.Welcome.primaryAction)
                    .typography(Typography.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(colors.accent)
            .opacity(phase >= 3 ? 1 : 0)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.bottom, Spacing.xl)
        .frame(maxWidth: .infinity)
        .background(colors.background.ignoresSafeArea())
        .task {
            await runEntrance()
        }
    }

    // MARK: - Animation Sequence

    private func runEntrance() async {
        // Phase 1: "Hello 👋" appears
        try? await Task.sleep(for: .milliseconds(600))
        withAnimation(.spring(duration: 0.7, bounce: 0.15)) {
            phase = 1
        }

        // Phase 2: Hello fades out, "Meet Eigin" types in
        try? await Task.sleep(for: .milliseconds(1500))
        withAnimation(.easeOut(duration: 0.4)) {
            phase = 2
        }
        try? await Task.sleep(for: .milliseconds(400))
        for character in meetEiginFull {
            meetEiginText.append(character)
            try? await Task.sleep(for: .milliseconds(80))
        }

        // Phase 3: Tagline, values, and buttons fade in
        try? await Task.sleep(for: .milliseconds(500))
        withAnimation(.easeOut(duration: 0.6)) {
            phase = 3
        }

        // Phase 4: Cycle through verbs
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.easeInOut(duration: 0.3)) {
                currentVerbIndex = (currentVerbIndex + 1) % cyclingVerbs.count
            }
        }
    }

    // MARK: - Subviews

    private func valueRow(
        icon: String,
        @ViewBuilder title: () -> some View,
        subtitle: String
    ) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(colors.accent)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                title()
                    .typography(Typography.headline)
                    .foregroundStyle(colors.textPrimary)
                    .lineLimit(1)

                Text(subtitle)
                    .typography(Typography.callout)
                    .foregroundStyle(colors.textSecondary)
                    .lineLimit(1)
            }
        }
    }
}

#Preview {
    OnboardingWelcome(onGetStarted: {})
        .previewEnvironment()
}
