import SwiftUI

/// Lets the user decide whether the agent may work in the background and reach
/// out occasionally. The explanation is spoken by the avatar via the scaffold;
/// this screen carries the two choices. Choosing background work persists the
/// preference and triggers a notification-permission request in the coordinator.
struct OnboardingInitiativeScreen: View {
    /// `true` to let the agent work in the background; `false` to stay reactive.
    let onChoose: (Bool) -> Void

    var body: some View {
        VStack(spacing: Sizing.PageLayout.ContentGrouping.gap) {
            Spacer()
            AppButton(Localized.Onboarding.Initiative.backgroundButton) { onChoose(true) }
            AppButton(Localized.Onboarding.Initiative.reactiveButton, variant: .secondary) {
                onChoose(false)
            }
        }
    }
}

#Preview {
    OnboardingScaffold(
        progress: 0.36,
        title: Localized.Onboarding.Flow.Initiative.title,
        text: Localized.Onboarding.Flow.Initiative.text
    ) {
        OnboardingInitiativeScreen(onChoose: { _ in })
    }
    .resolveTheme()
}
