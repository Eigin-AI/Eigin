import Factory
import SwiftUI

/// Every model a provider offers, with a switch each.
///
/// Three groups, by how much we can vouch for what is in them. Recommended is
/// the top of the catalogue ranking, and all of it arrives on: a provider you
/// just connected should be useful before you touch anything here. Other is
/// the rest of what we recognise: it all works, it is simply not what we would
/// reach for. Unknown is whatever else the provider's API listed — IDs the
/// catalogue has never seen, which may work, so they start off and say why.
///
/// This is the one list allowed to run to its end, and a list that long is
/// only usable searched, which is why the field sits above it.
struct ProviderModelsScreen: View {
    let provider: Provider

    @Environment(\.colors) private var colors
    @Environment(\.dismiss) private var dismiss
    @Injected(\.modelMetadataService) private var modelMetadataService
    @Injected(\.providerModelRefresher) private var refresher

    @State private var searchText = ""
    @State private var metadata: [String: ModelMetadata] = [:]
    @State private var recommended: [String] = []
    @State private var other: [String] = []
    @State private var unknown: [String] = []
    @State private var isRefreshing = false
    /// Gates the no-match notice until the first load has landed; before
    /// that, empty groups just mean we have not looked yet.
    @State private var isLoaded = false

    /// The top of the ranking gets its own group; the rest of the catalogue
    /// lands in Other.
    private static let recommendedLimit = 5

    var body: some View {
        SoftEdgeScrollView {
            VStack(spacing: Sizing.PageLayout.gap) {
                AppSearchField(
                    text: $searchText,
                    placeholder: Localized.Provider.Models.searchPrompt(
                        "\(provider.availableModels.count)"
                    )
                )

                if nothingShown {
                    AppEmptyState(
                        icon: Iconography.Functional.search,
                        title: searchText.isEmpty ? Localized.Model.Picker.noModels : Localized
                            .Model.Picker.noSearchResults,
                        description: searchText.isEmpty ? Localized.Model.Picker
                            .emptyHint : Localized.Provider.Models.noMatches(searchText)
                    ) {
                        if searchText.isEmpty {
                            AppButton(Localized.Common.Actions.retry, variant: .secondary) {
                                Task { await load() }
                            }
                            .disabled(isRefreshing)
                        } else {
                            AppButton(Localized.Model.Picker.clearSearch, variant: .secondary) {
                                searchText = ""
                            }
                        }
                    }
                }

                modelGroup(
                    title: Localized.Provider.Models.recommended,
                    models: recommended
                )

                modelGroup(title: Localized.Provider.Models.other, models: other)

                modelGroup(
                    title: Localized.Provider.Models.unknown,
                    models: unknown,
                    footnote: Localized.Provider.Models.unknownFootnote
                )
            }
            .padding(.horizontal, Spacing.n16)
            .padding(.top, Spacing.n8)
            .padding(.bottom, Spacing.n32)
        } header: {
            AppNavigationHeader(
                title: Localized.Provider.Models.title,
                leading: {
                    AppActionButton(
                        icon: Iconography.Functional.Arrow.left,
                        variant: .open,
                        size: .medium,
                        action: { dismiss() }
                    )
                },
                trailing: {
                    if isRefreshing {
                        ProgressView().padding(.trailing, Spacing.n4)
                    }
                }
            )
        }
        .onChange(of: searchText) { regroup() }
        .background(colors.surface.standard.base.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task { await load() }
    }

    // MARK: - Groups

    @ViewBuilder
    private func modelGroup(
        title: String,
        models: [String],
        footnote: String? = nil
    ) -> some View {
        if !models.isEmpty {
            AppContentGroup(label: title, footnote: footnote) {
                ForEach(models, id: \.self) { modelID in
                    AppRow(
                        AppRowSpec(
                            id: modelID,
                            title: displayName(for: modelID),
                            trailing: .toggle(
                                isOn: provider.enabledModels.contains(modelID),
                                isDisabled: false,
                                action: { toggle(modelID) }
                            )
                        )
                    )
                }
            }
        }
    }

    private var nothingShown: Bool {
        isLoaded && recommended.isEmpty && other.isEmpty && unknown.isEmpty
    }

    // MARK: - Data

    /// Cached catalog first, background refresh after — as the old picker did.
    private func load() async {
        await enrich(models: provider.availableModels)

        isRefreshing = true
        let previous = provider.availableModels
        if let refreshed = try? await refresher.refresh(provider, apiKeyOverride: nil),
           refreshed != previous
        {
            provider.availableModels = refreshed
            await enrich(models: refreshed)
        }
        isRefreshing = false
    }

    private func enrich(models: [String]) async {
        isLoaded = true
        let enriched = await modelMetadataService.enrich(
            modelIDs: models,
            provider: provider.name
        )
        metadata = Dictionary(
            enriched.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        regroup()
    }

    /// Deduplicate, search-filter, and split into the three vouching groups.
    private func regroup() {
        var seen = Set<String>()
        let matches = provider.availableModels
            .filter { seen.insert($0).inserted && matchesSearch($0) }

        let known = matches.filter { metadata[$0] != nil }
        let unknownModels = matches.filter { metadata[$0] == nil }

        let patternIndex = Dictionary(
            uniqueKeysWithValues: KnownModelCatalog.preferenceRanking.enumerated()
                .map { ($0.element, $0.offset) }
        )
        let knownSorted = known.sorted {
            let lhsRank = rank(of: $0, by: patternIndex)
            let rhsRank = rank(of: $1, by: patternIndex)
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            return $0 < $1
        }

        recommended = Array(knownSorted.prefix(Self.recommendedLimit))
        other = Array(knownSorted.dropFirst(Self.recommendedLimit))
        unknown = unknownModels
    }

    private func rank(of id: String, by patternIndex: [String: Int]) -> Int {
        guard let pattern = KnownModelCatalog.lookup(id)?.pattern,
              let rank = patternIndex[pattern]
        else { return .max }
        return rank
    }

    private func matchesSearch(_ id: String) -> Bool {
        guard !searchText.isEmpty else { return true }
        let query = searchText.lowercased()
        return displayName(for: id).lowercased().contains(query) || id.lowercased().contains(query)
    }

    // MARK: - Toggle

    /// New models start on when they are in the catalogue, off when they are
    /// not — turning one on is your call precisely because we cannot vouch.
    private func toggle(_ modelID: String) {
        if let index = provider.enabledModels.firstIndex(of: modelID) {
            provider.enabledModels.remove(at: index)
        } else {
            provider.enabledModels.append(modelID)
        }
        Haptics.light()
        // A disabled model may be the one a running agent is on; force-resolve now.
        Task { await AgentAutoRouting.forceResolveAgents(on: provider) }
    }

    // MARK: - Names

    private func displayName(for modelID: String) -> String {
        guard let meta = metadata[modelID], meta.name != modelID else { return modelID }
        if let tag = meta.versionTag {
            return "\(meta.name) (\(tag))"
        }
        return meta.name
    }
}
