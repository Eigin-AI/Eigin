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
        GridItem(.flexible(), spacing: Spacing.md),
        GridItem(.flexible(), spacing: Spacing.md),
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: Spacing.xl) {
                    VStack(spacing: Spacing.sm) {
                        Text(Localized.Provider.typeLabel)
                            .font(Typography.largeTitle)

                        Text(Localized.Onboarding.Provider.cloudExplanation)
                            .font(Typography.body)
                            .foregroundStyle(colors.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, Spacing.xl)

                    // OAuth providers — featured options
                    ForEach(oauthPresets) { preset in
                        Button {
                            onSelect(preset)
                        } label: {
                            HStack(spacing: Spacing.sm) {
                                providerIcon(for: preset)

                                Text(Localized.Provider.Setup.oauthConnect(preset.name))
                                    .font(Typography.headline)
                                    .foregroundStyle(colors.textPrimary)

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(Typography.caption)
                                    .foregroundStyle(colors.textSecondary)
                            }
                            .padding(Spacing.md)
                            .background(colors.surface, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }

                    // API key — collapsible
                    VStack(spacing: Spacing.md) {
                        HStack {
                            Text(Localized.Provider.Setup.apiKeyAlternative)
                                .font(Typography.callout)
                                .foregroundStyle(colors.textSecondary)

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(Typography.caption)
                                .foregroundStyle(colors.textSecondary)
                                .rotationEffect(showAPIKeyOptions ? .degrees(90) : .zero)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(Animations.smooth) {
                                showAPIKeyOptions.toggle()
                            }
                        }

                        if showAPIKeyOptions {
                            LazyVGrid(columns: columns, spacing: Spacing.md) {
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
                .padding(.horizontal, Spacing.lg)
            }

            // Connected providers
            if !cloudProviders.isEmpty {
                VStack(spacing: Spacing.sm) {
                    ForEach(cloudProviders) { provider in
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(colors.accent)
                            Text(provider.name)
                                .font(Typography.body)
                                .foregroundStyle(colors.textPrimary)
                            Spacer()
                        }
                    }
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.md)

                Button {
                    onContinue?()
                } label: {
                    Text(Localized.Common.Actions.continue)
                        .font(Typography.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(colors.accent)
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.lg)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(colors.background.ignoresSafeArea())
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
                .foregroundStyle(colors.textSecondary)
                .frame(width: 36, height: 36)
        }
    }

    private func presetTile(_ preset: ProviderPreset) -> some View {
        VStack(spacing: Spacing.sm) {
            providerIcon(for: preset)

            Text(preset.name)
                .font(Typography.callout)
                .foregroundStyle(colors.textPrimary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.lg)
        .padding(.horizontal, Spacing.sm)
        .background(colors.surface, in: RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    OnboardingProviderSetup { _ in }
        .previewEnvironment()
}
