import SwiftUI

/// The opening ethos moment. The spoken ethos comes from the avatar via the
/// scaffold; this screen only carries the action.
struct OnboardingWelcome: View {
    let onBegin: () -> Void

    var body: some View {
        VStack {
            Spacer()
            AppButton(Localized.Onboarding.Welcome.beginButton) { onBegin() }
        }
    }
}

#Preview {
    OnboardingScaffold(
        progress: 0.0,
        showsProgress: false,
        entrance: true,
        title: Localized.Onboarding.Flow.Welcome.title,
        text: Localized.Onboarding.Flow.Welcome.text,
        titleDelay: .seconds(1)
    ) {
        OnboardingWelcome(onBegin: {})
    }
    .resolveTheme()
}
