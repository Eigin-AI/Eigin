import SwiftUI

struct ProviderPicker: View {
    @Environment(\.colors) private var colors

    @State private var searchText = ""

    private var filteredPresets: [ProviderPreset] {
        let presets: [ProviderPreset] = if searchText.isEmpty {
            ProviderPreset.all
        } else {
            ProviderPreset.all.filter {
                $0.name.localizedCaseInsensitiveContains(searchText)
            }
        }
        return presets.filter { !ProviderPreset.isLocal($0.baseURL) }
    }

    private var localPresets: [ProviderPreset] {
        let locals = ProviderPreset.all.filter { ProviderPreset.isLocal($0.baseURL) }
        if searchText.isEmpty { return locals }
        return locals.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var columns: [GridItem] {
        [
            GridItem(.flexible(), spacing: Spacing.md),
            GridItem(.flexible(), spacing: Spacing.md),
        ]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: Spacing.md) {
                    ForEach(filteredPresets) { preset in
                        NavigationLink(value: preset) {
                            ProviderTile(preset: preset, colors: colors)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Spacing.md)

                if searchText.isEmpty {
                    NavigationLink(value: "custom") {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "plus.circle")
                                .font(.title3)
                            Text(Localized.Provider.Picker.customProvider)
                                .font(Typography.body)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(Typography.caption)
                                .foregroundStyle(colors.textSecondary)
                        }
                        .padding(Spacing.md)
                        .background(colors.surface, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, Spacing.md)
                    .padding(.top, Spacing.sm)
                }

                if !localPresets.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        ForEach(localPresets) { preset in
                            NavigationLink(value: preset) {
                                LocalProviderTile(preset: preset, colors: colors)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.bottom, Spacing.lg)
                }
            }
            .background(colors.background.ignoresSafeArea())
            .navigationTitle(Localized.Settings.Action.addProvider)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: Localized.Provider.Picker.searchPrompt)
            .navigationDestination(for: ProviderPreset.self) { preset in
                if ProviderPreset.isLocal(preset.baseURL) {
                    LocalProviderView(preset: preset)
                } else if preset.authMethod == .oAuthPKCE {
                    OAuthProviderView(preset: preset)
                } else {
                    AddProvider(preset: preset)
                }
            }
            .navigationDestination(for: String.self) { _ in
                AddProvider()
            }
        }
    }
}

private struct LocalProviderTile: View {
    let preset: ProviderPreset
    let colors: ResolvedColors

    var body: some View {
        HStack(spacing: Spacing.sm) {
            if let systemImage = preset.systemImage {
                Image(systemName: systemImage)
                    .font(.title3)
            }
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.sm) {
                    Text(preset.name)
                        .font(Typography.body)
                    Text(Localized.Provider.Picker.experimental)
                        .font(Typography.caption)
                        .foregroundStyle(colors.textSecondary)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, 2)
                        .background(colors.surfaceSecondary, in: Capsule())
                }
                Text(preset.helpText)
                    .font(Typography.caption)
                    .foregroundStyle(colors.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(Typography.caption)
                .foregroundStyle(colors.textSecondary)
        }
        .padding(Spacing.md)
        .background(colors.surface, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, Spacing.md)
    }
}

private struct ProviderTile: View {
    let preset: ProviderPreset
    let colors: ResolvedColors

    var body: some View {
        VStack(spacing: Spacing.sm) {
            if let logo = preset.logo {
                Image(uiImage: logo)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 40, height: 40)
            } else if let systemImage = preset.systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 28))
                    .foregroundStyle(colors.textSecondary)
                    .frame(width: 40, height: 40)
            } else {
                Text(String(preset.name.prefix(1)))
                    .font(Typography.headline)
                    .foregroundStyle(colors.textSecondary)
                    .frame(width: 40, height: 40)
            }

            Text(preset.name)
                .font(Typography.callout)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.lg)
        .padding(.horizontal, Spacing.sm)
        .background(colors.surface, in: RoundedRectangle(cornerRadius: 12))
    }
}
