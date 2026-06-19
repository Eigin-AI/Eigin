import SwiftUI

/// Asks the user's name. Three stacked rows mirror the inference screen's
/// layout: a quiet link addressing why a private app asks, the full-width field,
/// and a full-width button to continue.
struct OnboardingNameScreen: View {
    @Binding var name: String
    let onContinue: () -> Void

    @Environment(\.colors) private var colors
    @State private var showPrivacy = false

    private var trimmed: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: Spacing.n16) {
            Spacer()

            Button { showPrivacy = true } label: {
                Text(Localized.Onboarding.Name.privacyLink)
                    .typography(Typography.navTab)
                    .foregroundStyle(colors.text.standard.link)
            }
            .buttonStyle(.plain)

            VStack(spacing: Sizing.PageLayout.ContentGrouping.gap) {
                AppTextInput(label: Localized.Onboarding.Name.fieldLabel, text: $name)
                    .onSubmit(submit)

                AppButton(Localized.Onboarding.Name.continueButton) { submit() }
                    .disabled(trimmed.isEmpty)
            }
        }
        .appSheet(
            isPresented: $showPrivacy,
            title: Localized.Onboarding.Name.privacySheetTitle,
            detents: [.medium],
            fitsContent: true
        ) {
            Text(Localized.Onboarding.Name.privacySheetText)
                .typography(Typography.body)
                .foregroundStyle(colors.text.standard.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.n24)
        }
    }

    private func submit() {
        guard !trimmed.isEmpty else { return }
        onContinue()
    }
}

#Preview {
    OnboardingScaffold(
        progress: 0.12,
        title: Localized.Onboarding.Flow.Name.title,
        text: Localized.Onboarding.Flow.Name.text
    ) {
        OnboardingNameScreen(name: .constant(""), onContinue: {})
    }
    .resolveTheme()
}
