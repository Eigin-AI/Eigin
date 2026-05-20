import SwiftUI

/// User selection from the provider sheet.
enum ProviderSelection {
    case preset(ProviderPreset)
    case custom
}

/// Content for the provider selection sheet.
///
/// Shared between onboarding and Settings → Connections. Presents OAuth
/// providers as featured buttons and API key providers in a collapsible grid,
/// with a custom-provider tile appended to the grid.
struct ProviderSelectSheetContent: View {
    @Environment(\.colors) private var colors

    let onSelect: (ProviderSelection) -> Void

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
        GridItem(.flexible(), spacing: Sizing.PageLayout.ContentGrouping.gap),
        GridItem(.flexible(), spacing: Sizing.PageLayout.ContentGrouping.gap),
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
                            onSelect(.preset(preset))
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
                    VStack(spacing: Sizing.PageLayout.ContentGrouping.gap) {
                        LazyVGrid(
                            columns: columns,
                            spacing: Sizing.PageLayout.ContentGrouping.gap
                        ) {
                            ForEach(apiKeyPresets) { preset in
                                Button { onSelect(.preset(preset)) } label: {
                                    presetTile(preset)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        AppSubtleActionButton(
                            Localized.Provider.Picker.customProvider,
                            icon: Iconography.Functional.plus,
                            size: .medium
                        ) {
                            onSelect(.custom)
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
