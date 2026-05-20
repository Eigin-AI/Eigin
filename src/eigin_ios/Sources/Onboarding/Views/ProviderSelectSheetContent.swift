import SwiftUI

/// Content for the provider selection sheet.
///
/// Presents OAuth providers as featured buttons and API key providers in a
/// collapsible grid. Calls back with the selected preset.
struct ProviderSelectSheetContent: View {
    @Environment(\.colors) private var colors

    let onSelect: (ProviderPreset) -> Void

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
        VStack(spacing: Sizing.PageLayout.gap) {
            VStack(spacing: Sizing.PageLayout.ContentGrouping.gap) {
                // OAuth providers — featured options
                ForEach(oauthPresets) { preset in
                    HStack(spacing: Spacing.n16) {
                        if let emoji = preset.region?.emoji {
                            Text(emoji)
                                .font(.system(size: 28))
                        }

                        AppSubtleActionButton(
                            Localized.Provider.Setup.oauthConnect(preset.name),
                            icon: Iconography.Functional.Arrow.right,
                            size: .medium
                        ) {
                            onSelect(preset)
                        }
                    }
                }
            }

            // API key — collapsible
            VStack(spacing: Sizing.PageLayout.HeaderGrouping.gap) {
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
        VStack(spacing: Spacing.n16) {
            providerIcon(for: preset)

            Text(preset.name)
                .typography(Typography.button)
                .foregroundStyle(colors.text.standard.base)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.n24)
        .padding(.horizontal, Spacing.n8)
        .background(
            colors.button.standard.secondary,
            in: RoundedRectangle(cornerRadius: Radius.card)
        )
    }
}

#Preview {
    ProviderSelectSheetContent { _ in }
        .previewEnvironment()
}
