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
            GridItem(.flexible(), spacing: Spacing.n16),
            GridItem(.flexible(), spacing: Spacing.n16),
        ]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: Spacing.n16) {
                    ForEach(filteredPresets) { preset in
                        NavigationLink(value: preset) {
                            ProviderTile(preset: preset, colors: colors)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Spacing.n16)

                if searchText.isEmpty {
                    NavigationLink(value: "custom") {
                        HStack(spacing: Spacing.n8) {
                            Image(systemName: "plus.circle")
                                .font(.title3)
                            Text(Localized.Provider.Picker.customProvider)
                                .typography(Typography.navTab)
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
                    .padding(.horizontal, Spacing.n16)
                    .padding(.top, Spacing.n8)
                }

                if !localPresets.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.n8) {
                        ForEach(localPresets) { preset in
                            NavigationLink(value: preset) {
                                LocalProviderTile(preset: preset, colors: colors)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.bottom, Spacing.n24)
                }
            }
            .background(colors.surface.standard.base.ignoresSafeArea())
            .navigationTitle(Localized.Settings.Action.addProvider, style: Typography.titleXl)
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
        HStack(spacing: Spacing.n8) {
            if let systemImage = preset.systemImage {
                Image(systemName: systemImage)
                    .font(.title3)
            }
            VStack(alignment: .leading, spacing: Spacing.n4) {
                HStack(spacing: Spacing.n8) {
                    Text(preset.name)
                        .typography(Typography.navTab)
                    Text(Localized.Provider.Picker.experimental)
                        .typography(Typography.miniLabel)
                        .foregroundStyle(colors.text.standard.muted)
                        .padding(.horizontal, Spacing.n8)
                        .padding(.vertical, 2)
                        .background(colors.surface.standard.base, in: Capsule())
                }
                Text(preset.helpText)
                    .typography(Typography.miniLabel)
                    .foregroundStyle(colors.text.standard.muted)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .typography(Typography.miniLabel)
                .foregroundStyle(colors.text.standard.muted)
        }
        .padding(Spacing.n16)
        .background(colors.surface.standard.alternative, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, Spacing.n16)
    }
}

private struct ProviderTile: View {
    let preset: ProviderPreset
    let colors: ResolvedColors

    var body: some View {
        VStack(spacing: Spacing.n8) {
            if let logo = preset.logo {
                Image(uiImage: logo)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 40, height: 40)
            } else if let systemImage = preset.systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 28))
                    .foregroundStyle(colors.text.standard.muted)
                    .frame(width: 40, height: 40)
            } else {
                Text(String(preset.name.prefix(1)))
                    .typography(Typography.titleXS)
                    .foregroundStyle(colors.text.standard.muted)
                    .frame(width: 40, height: 40)
            }

            Text(preset.name)
                .typography(Typography.navTab)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.n24)
        .padding(.horizontal, Spacing.n8)
        .background(colors.surface.standard.alternative, in: RoundedRectangle(cornerRadius: 12))
    }
}
