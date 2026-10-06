import SwiftUI

/// User selection from the provider sheet: a preset plus the way you want
/// to connect it — the group you picked the row from — or anything at all
/// via address (the custom route).
enum ProviderSelection {
    case preset(ProviderPreset, method: ProviderPreset.AuthMethod)
    case custom
}

/// The catalogue of providers, grouped by what you will be asked to do rather
/// than by the protocol behind it. Sign-in first because it asks least of you.
/// Connect-by-address is always the last thing in the sheet, so the way in for
/// anything we have never heard of never moves. Shared between onboarding and
/// the connections hub.
struct ProviderSelectSheetContent: View {
    @Environment(\.colors) private var colors

    /// Presets already connected, omitted entirely: you reached this sheet
    /// from the list they are on, so offering them again would be offering a
    /// thing you cannot do.
    var connectedBaseURLs: [String] = []

    let onSelect: (ProviderSelection) -> Void

    @State private var searchText = ""

    init(connectedBaseURLs: [String] = [], onSelect: @escaping (ProviderSelection) -> Void) {
        self.connectedBaseURLs = connectedBaseURLs
        self.onSelect = onSelect
    }

    /// Sign-in route: OAuth presets. API-key route: everything that can take
    /// a key — a preset offering both genuinely appears in both groups,
    /// because the group you pick from IS the way you want to connect.
    private var signInPresets: [ProviderPreset] {
        filtered(
            ProviderPreset.all.filter {
                $0.authMethod == .oAuthPKCE || $0.authMethod == .chatGPTSubscription
            }
        )
    }

    private var apiKeyPresets: [ProviderPreset] {
        filtered(
            ProviderPreset.all.filter {
                ($0.authMethod == .apiKey || $0.apiKeyURL != nil)
                    && !ProviderPreset.isLocal($0.baseURL)
                    && !ProviderPreset.isRelay($0.baseURL)
            }
        )
    }

    private func filtered(_ presets: [ProviderPreset]) -> [ProviderPreset] {
        presets
            .filter { !connectedBaseURLs.contains($0.baseURL) }
            .filter { name in
                guard !searchText.isEmpty else { return true }
                return name.name.lowercased().contains(searchText.lowercased())
            }
    }

    private var nothingFound: Bool {
        signInPresets.isEmpty && apiKeyPresets.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Sizing.PageLayout.gap) {
                AppSearchField(
                    text: $searchText,
                    placeholder: Localized.Provider.Picker.searchPrompt
                )

                if nothingFound {
                    AppNotice(
                        tone: .info,
                        title: Localized.Provider.Picker.unknownNoticeTitle,
                        body: Localized.Provider.Picker.unknownNoticeBody
                    )
                }

                if !signInPresets.isEmpty {
                    AppRowsGroup(
                        label: Localized.Provider.Picker.Group.signIn,
                        rows: signInPresets.map { preset in
                            AppRowSpec(
                                id: preset.id,
                                title: preset.name,
                                icon: markIcon(for: preset),
                                action: { onSelect(.preset(preset, method: preset.authMethod)) }
                            )
                        }
                    )
                }

                if !apiKeyPresets.isEmpty {
                    AppRowsGroup(
                        label: Localized.Provider.Picker.Group.apiKey,
                        rows: apiKeyPresets.map { preset in
                            AppRowSpec(
                                id: preset.id,
                                title: preset.name,
                                icon: markIcon(for: preset),
                                action: { onSelect(.preset(preset, method: .apiKey)) }
                            )
                        }
                    )
                }

                // The way in for anything we have never heard of never moves.
                AppRowsGroup(
                    footnote: Localized.Provider.Picker.addressFootnote,
                    rows: [
                        AppRowSpec(
                            id: "address",
                            title: Localized.Provider.Picker.connectByAddress,
                            icon: Iconography.Functional.globe,
                            action: { onSelect(.custom) }
                        ),
                    ]
                )

                // Third-party disclosure before the user connects a provider of
                // their own (App Store guideline 5.1.2).
                ThirdPartyDisclosureText(variant: .ownProvider)
            }
            .padding(.horizontal, Spacing.n16)
            .padding(.top, Spacing.n8)
            .padding(.bottom, Spacing.n32)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func markIcon(for preset: ProviderPreset) -> Image? {
        preset.logo.map(Image.init(uiImage:))
    }
}

#Preview {
    ProviderSelectSheetContent { _ in }
        .previewEnvironment()
}
