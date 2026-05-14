import SwiftData
import SwiftUI

/// Provider picker screen in onboarding. Calls back with the selected preset.
struct OnboardingProviderSetup: View {
    @Environment(\.colors) private var colors
    @Query(sort: \Provider.createdAt) private var allProviders: [Provider]

    private var cloudProviders: [Provider] {
        allProviders.filter { !ProviderPreset.isLocal($0.baseURL) }
    }

    let onSelect: (ProviderPreset) -> Void
    var onContinue: (() -> Void)?

    @State private var showAPIKeyOptions = false

    private var oauthPresets: [ProviderPreset] {
        ProviderPreset.all.filter { $0.authMethod == .oAuthPKCE }
    }

    private var apiKeyPresets: [ProviderPreset] {
        ProviderPreset.all.filter {
            $0.authMethod == .apiKey && !ProviderPreset.isLocal($0.baseURL)
        }
    }

    private let columns = [
        GridItem(.flexible(), spacing: Spacing.n16),
        GridItem(.flexible(), spacing: Spacing.n16),
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: Spacing.n32) {
                    VStack(spacing: Spacing.n8) {
                        Text(Localized.Provider.typeLabel)
                            .typography(Typography.titleXl)

                        Text(Localized.Onboarding.Provider.cloudExplanation)
                            .typography(Typography.body)
                            .foregroundStyle(colors.text.standard.muted)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, Spacing.n32)

                    // OAuth providers — featured options
                    ForEach(oauthPresets) { preset in
                        Button {
                            onSelect(preset)
                        } label: {
                            HStack(spacing: Spacing.n8) {
                                providerIcon(for: preset)

                                Text(Localized.Provider.Setup.oauthConnect(preset.name))
                                    .typography(Typography.titleXS)
                                    .foregroundStyle(colors.text.standard.base)

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .typography(Typography.miniLabel)
                                    .foregroundStyle(colors.text.standard.muted)
                            }
                            .padding(Spacing.n16)
                            .background(
                                colors.surface.standard.alternative,
                                in: RoundedRectangle(cornerRadius: 12)
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    // API key — collapsible
                    VStack(spacing: Spacing.n16) {
                        HStack {
                            Text(Localized.Provider.Setup.apiKeyAlternative)
                                .typography(Typography.navTab)
                                .foregroundStyle(colors.text.standard.muted)

                            Spacer()

                            Image(systemName: "chevron.right")
                                .typography(Typography.miniLabel)
                                .foregroundStyle(colors.text.standard.muted)
                                .rotationEffect(showAPIKeyOptions ? .degrees(90) : .zero)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(Animations.smooth) {
                                showAPIKeyOptions.toggle()
                            }
                        }

                        if showAPIKeyOptions {
                            LazyVGrid(columns: columns, spacing: Spacing.n16) {
                                ForEach(apiKeyPresets) { preset in
                                    Button { onSelect(preset) } label: {
                                        presetTile(preset)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, Spacing.n24)
            }

            // Connected providers
            if !cloudProviders.isEmpty {
                VStack(spacing: Spacing.n8) {
                    ForEach(cloudProviders) { provider in
                        HStack(spacing: Spacing.n8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(colors.accent)
                            Text(provider.name)
                                .typography(Typography.navTab)
                                .foregroundStyle(colors.text.standard.base)
                            Spacer()
                        }
                    }
                }
                .padding(.horizontal, Spacing.n24)
                .padding(.top, Spacing.n16)

                Button {
                    onContinue?()
                } label: {
                    Text(Localized.Common.Actions.continue)
                        .typography(Typography.titleXS)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(colors.accent)
                .padding(.horizontal, Spacing.n24)
                .padding(.vertical, Spacing.n24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(colors.surface.standard.base.ignoresSafeArea())
    }

    // MARK: - Subviews

    @ViewBuilder
    private func providerIcon(for preset: ProviderPreset) -> some View {
        if let logo = preset.logo {
            Image(uiImage: logo)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 36, height: 36)
        } else if let systemImage = preset.systemImage {
            Image(systemName: systemImage)
                .font(.system(size: 24))
                .foregroundStyle(colors.text.standard.muted)
                .frame(width: 36, height: 36)
        }
    }

    private func presetTile(_ preset: ProviderPreset) -> some View {
        VStack(spacing: Spacing.n8) {
            providerIcon(for: preset)

            Text(preset.name)
                .typography(Typography.navTab)
                .foregroundStyle(colors.text.standard.base)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.n24)
        .padding(.horizontal, Spacing.n8)
        .background(colors.surface.standard.alternative, in: RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    OnboardingProviderSetup { _ in }
        .previewEnvironment()
}
