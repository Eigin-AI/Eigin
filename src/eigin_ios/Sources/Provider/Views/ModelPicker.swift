import Factory
import SwiftUI

/// Selects Auto or an enabled model from the provider's refreshable catalog.
struct ModelPicker: View {
    let provider: Provider
    @Binding var selectedModel: String
    @Binding var isAuto: Bool

    @Environment(\.colors) private var colors
    @Environment(\.dismiss) private var dismiss
    @Injected(\.modelMetadataService) private var modelMetadataService
    @Injected(\.providerModelRefresher) private var refresher

    @State private var searchText = ""
    @State private var metadata: [String: ModelMetadata] = [:]
    @State private var rankedModels: [String] = []
    @State private var unknownModels: [String] = []
    @State private var isLoaded = false
    @State private var isRefreshing = false

    var body: some View {
        AppSecondaryScreen(title: Localized.Model.Picker.title, fillsViewport: true) {
            if selectableModels.isEmpty {
                if isLoaded, !isRefreshing {
                    AppEmptyState(
                        icon: Iconography.Functional.sparkles,
                        title: Localized.Model.Picker.noModels,
                        description: Localized.Model.Picker.emptyHint
                    )
                } else {
                    AppLoadingState(title: Localized.Model.Picker.loading)
                }
            } else {
                AppSearchField(text: $searchText, placeholder: Localized.Model.Picker.searchPrompt)
                content
            }
        } trailing: {
            if isRefreshing, !selectableModels.isEmpty {
                SweepRing(size: Spacing.n16, stroke: 2)
                    .accessibilityLabel(Localized.Model.Picker.loading)
            }
        }
        .onChange(of: searchText) { prepare() }
        .task {
            // Cached models remain selectable while the provider refreshes.
            await enrich(models: selectableModels)
            guard !Task.isCancelled else { return }
            isLoaded = true
            isRefreshing = true
            _ = try? await refresher.refresh(provider, apiKeyOverride: nil)
            isRefreshing = false
            guard !Task.isCancelled else { return }
            await enrich(models: selectableModels)
        }
    }

    @ViewBuilder
    private var content: some View {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            AppRowsGroup(footnote: Localized.Model.Picker.Auto.footnote, rows: [AppRowSpec(
                title: Localized.Model.Picker.Auto.title,
                description: isAuto && !selectedModel.isEmpty
                    ? displayName(for: selectedModel) : Localized.Model.Picker.Auto.description,
                accessory: isAuto ? .check : .none,
                action: { isAuto = true; dismiss() }
            )])
            .accessibilityAddTraits(isAuto ? .isSelected : [])
        }
        if !rankedModels.isEmpty {
            AppContentGroup(label: Localized.Model.Picker.otherRecommended) {
                modelRows(rankedModels)
            }
        }
        if !unknownModels.isEmpty {
            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                AppDisclosure(
                    Localized.Model.Picker.allModels,
                    description: unknownModels.count == 1
                        ? Localized.Model.Picker.oneMoreModel
                        : Localized.Model.Picker.moreModels("\(unknownModels.count)")
                ) {
                    VStack(spacing: 0) { modelRows(unknownModels) }
                }
            } else {
                AppContentGroup(label: Localized.Model.Picker.otherModels) {
                    modelRows(unknownModels)
                }
            }
        }
        if isLoaded, !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           rankedModels.isEmpty, unknownModels.isEmpty
        {
            AppEmptyState(
                icon: Iconography.Functional.search,
                title: Localized.Model.Picker.noSearchResults,
                description: Localized.Model.Picker.noSearchHint(searchText)
            ) {
                AppButton(Localized.Model.Picker.clearSearch, variant: .secondary) {
                    searchText = ""
                }
            }
        }
    }

    private func modelRows(_ models: [String]) -> some View {
        ForEach(Array(models.enumerated()), id: \.element) { index, modelID in
            if index > 0 { RowHairline() }
            let selected = !isAuto && selectedModel == modelID
            AppRow(AppRowSpec(
                id: modelID,
                title: displayName(for: modelID),
                description: subtitle(for: modelID),
                accessory: selected ? .check : .none,
                action: { selectedModel = modelID; isAuto = false; dismiss() }
            ))
            .accessibilityAddTraits(selected ? .isSelected : [])
        }
    }

    // MARK: - Preparation

    /// Enriches the given model IDs with catalog metadata, then rebuilds the grouped lists.
    /// What the picker offers: the models the provider screens left enabled,
    /// minus anything the provider has retired since.
    private var selectableModels: [String] {
        let available = Set(provider.availableModels)
        return provider.availableModels.isEmpty
            ? provider.enabledModels
            : provider.enabledModels.filter { available.contains($0) }
    }

    private func enrich(models: [String]) async {
        let enriched = await modelMetadataService.enrich(
            modelIDs: models,
            provider: provider.name
        )
        metadata = Dictionary(
            enriched.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        prepare()
    }

    /// Filters, groups, and sorts the catalog once into stored state so `body` only renders
    /// prepared arrays. A precomputed rank map avoids repeating catalog lookups per comparison.
    private func prepare() {
        // Deduplicate defensively: a cached list (or a provider that lists a model twice) would
        // otherwise crash the rank-map build and yield non-unique `ForEach` ids.
        var seen = Set<String>()
        let all = selectableModels.filter { seen.insert($0).inserted }

        let known = all.filter { metadata[$0] != nil && matchesSearch($0) }
        let unknown = all.filter { metadata[$0] == nil && matchesSearch($0) }

        let patternIndex = Dictionary(
            uniqueKeysWithValues: KnownModelCatalog.preferenceRanking.enumerated()
                .map { ($0.element, $0.offset) }
        )
        let rankByModel: [String: Int] = Dictionary(
            uniqueKeysWithValues: known.map { id in
                guard let pattern = KnownModelCatalog.lookup(id)?.pattern,
                      let rank = patternIndex[pattern]
                else {
                    return (id, Int.max)
                }
                return (id, rank)
            }
        )

        rankedModels = known
            .sorted { (rankByModel[$0] ?? .max) < (rankByModel[$1] ?? .max) }
        unknownModels = unknown
    }

    private func matchesSearch(_ id: String) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return true }
        return displayName(for: id).lowercased().contains(query)
            || id.lowercased().contains(query)
    }

    // MARK: - Helpers

    private func displayName(for modelID: String) -> String {
        guard let meta = metadata[modelID], meta.name != modelID else {
            return modelID
        }
        if let tag = meta.versionTag {
            return "\(meta.name) (\(tag))"
        }
        return meta.name
    }

    private func subtitle(for modelID: String) -> String? {
        guard let meta = metadata[modelID] else { return nil }
        var parts: [String] = []
        if let output = meta.outputCostPerMillion {
            parts.append(costIndicator(output))
        }
        if let ctx = meta.contextWindow {
            parts.append(compactContext(ctx))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func costIndicator(_ outputCostPerMillion: Double) -> String {
        let thresholds = KnownModelCatalog.costTerciles
        if outputCostPerMillion <= thresholds.lower { return "$" }
        if outputCostPerMillion <= thresholds.upper { return "$$" }
        return "$$$"
    }

    private func compactContext(_ tokens: Int) -> String {
        if tokens >= 1_000_000 {
            let m = (Double(tokens) / 1_000_000).rounded()
            return "\(Int(m))M context"
        }
        let k = Int((Double(tokens) / 1000).rounded())
        return "\(k)K context"
    }
}

// MARK: - Previews

private func previewProvider(name: String, models: [String]) -> Provider {
    let provider = Provider(name: name, baseURL: "https://fake.local")
    provider.availableModels = models
    return provider
}

#Preview("Typical catalog") {
    @Previewable @State var selected = "gpt-5.5"
    @Previewable @State var isAuto = true
    let provider = previewProvider(
        name: "OpenAI",
        models: [
            "gpt-5.5", "gpt-5.4", "gpt-5.4-mini",
            "claude-sonnet-4-6", "gemini-3.5-flash",
            "o3-mini", "text-embedding-3-large", "whisper-1",
        ]
    )
    return NavigationStack {
        ModelPicker(provider: provider, selectedModel: $selected, isAuto: $isAuto)
    }
    .previewEnvironment()
}

#Preview("Large catalog") {
    @Previewable @State var selected = "claude-sonnet-4-6"
    @Previewable @State var isAuto = false
    let known = ["claude-sonnet-4-6", "gpt-5.5", "gpt-5.4", "gemini-3.5-flash"]
    let unknown = (1 ... 140).map { "vendor/experimental-model-\($0)" }
    let provider = previewProvider(name: "OpenRouter", models: known + unknown)
    return NavigationStack {
        ModelPicker(provider: provider, selectedModel: $selected, isAuto: $isAuto)
    }
    .previewEnvironment()
}

#Preview("First connect (loading)") {
    @Previewable @State var selected = ""
    @Previewable @State var isAuto = true
    // Empty cache: the preview refresher simulates a slow first-connect, so this shows the
    // "Loading models…" state for ~2s and then populates as the catalog is discovered.
    let provider = previewProvider(name: "New Provider", models: [])
    return NavigationStack {
        ModelPicker(provider: provider, selectedModel: $selected, isAuto: $isAuto)
    }
    .previewEnvironment()
}
