import Factory
import SwiftUI

/// Model picker: automatic selection at the top, or a specific model for those who want
/// to choose.
///
/// Below the Auto row come "Recommended" (ordered by preference ranking) and "Other".
///
/// The provider's catalog is treated as a refreshable cache: the cached list renders instantly,
/// then a background refresh updates it so newly added models appear and retired ones disappear.
/// Grouping and sorting are computed once off the render path (not in `body`) so the view stays
/// responsive even for providers with large catalogs.
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
    @State private var isOtherCollapsed = true

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            AppNavigationHeader(
                title: Localized.Model.Picker.title,
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
                        ProgressView()
                            .padding(.trailing, Spacing.n4)
                    }
                }
            )

            List {
                if selectableModels.isEmpty {
                    // No cached models: keep the loading state until the background refresh
                    // resolves,
                    // then show a genuine empty-catalog message if it still came back empty.
                    if isLoaded, !isRefreshing {
                        emptyCatalog
                    } else {
                        loadingPlaceholder
                    }
                } else {
                    content
                }
            }
            .searchable(text: $searchText, prompt: "Search models")
            .onChange(of: searchText) { prepare() }
            .contentMargins(.top, 0, for: .scrollContent)
            .scrollContentBackground(.hidden)
        }
        .background(colors.surface.standard.base.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task {
            // Render the cached catalog immediately, then refresh in the background so the
            // list reflects what the provider serves now. Only the enabled
            // models appear: the switches on the provider screens decide
            // what this picker offers, and a refresh never re-widens it.
            await enrich(models: selectableModels)
            isLoaded = true

            isRefreshing = true
            _ = try? await refresher.refresh(provider, apiKeyOverride: nil)
            isRefreshing = false
            await enrich(models: selectableModels)
        }
    }

    @ViewBuilder
    private var content: some View {
        if searchText.isEmpty {
            Section {
                autoRow
            }
        }

        if !rankedModels.isEmpty {
            Section {
                ForEach(rankedModels, id: \.self) { modelID in
                    modelRow(modelID)
                }
            } header: {
                Text(Localized.Model.Picker.otherRecommended)
                    .typography(Typography.miniLabel)
            }
        }

        if !unknownModels.isEmpty {
            Section {
                if !isOtherCollapsed {
                    ForEach(unknownModels, id: \.self) { modelID in
                        modelRow(modelID)
                    }
                }
            } header: {
                Button {
                    withAnimation { isOtherCollapsed.toggle() }
                } label: {
                    HStack(spacing: Spacing.n8) {
                        Image(systemName: isOtherCollapsed ? "chevron.right" : "chevron.down")
                            .typography(Typography.miniLabel)
                            .foregroundStyle(colors.text.standard.muted)
                        Text(Localized.Model.Picker.allModels)
                        Text(verbatim: "\(unknownModels.count)")
                            .typography(Typography.miniLabel)
                            .foregroundStyle(colors.text.standard.muted)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }

        if !searchText.isEmpty, rankedModels.isEmpty, unknownModels.isEmpty {
            Section {
                infoRow(Localized.Model.Picker.noSearchResults)
            }
        }
    }

    /// Hands model choice back to the router. The model in use is shown as subtext so a
    /// curious user can still see what is running.
    private var autoRow: some View {
        Button {
            isAuto = true
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Localized.Model.Picker.Auto.title)
                        .typography(Typography.titleXS)
                        .foregroundStyle(colors.text.standard.base)

                    // On auto, what it picked is the useful thing to show. Off it, the
                    // offer is.
                    if isAuto, !selectedModel.isEmpty {
                        Text(Localized.Model.Picker.Auto.current(displayName(for: selectedModel)))
                            .typography(Typography.miniLabel)
                            .foregroundStyle(colors.accent)
                    } else {
                        Text(Localized.Model.Picker.Auto.description)
                            .typography(Typography.miniLabel)
                            .foregroundStyle(colors.text.standard.muted)
                    }
                }

                Spacer()

                if isAuto {
                    Image(systemName: "checkmark")
                        .foregroundStyle(colors.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var loadingPlaceholder: some View {
        Section {
            HStack(spacing: Spacing.n8) {
                ProgressView()
                Text(Localized.Model.Picker.loading)
                    .typography(Typography.body)
                    .foregroundStyle(colors.text.standard.muted)
            }
            .padding(.vertical, Spacing.n4)
        }
    }

    private var emptyCatalog: some View {
        Section {
            infoRow(Localized.Model.Picker.noModels)
        }
    }

    private func infoRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.n8) {
            Image(systemName: "info.circle")
                .foregroundStyle(colors.text.standard.muted)
                .typography(Typography.miniLabel)
            Text(text)
                .typography(Typography.miniLabel)
                .foregroundStyle(colors.text.standard.muted)
        }
        .padding(.vertical, Spacing.n4)
    }

    // MARK: - Model Row

    private func modelRow(_ modelID: String) -> some View {
        Button {
            selectedModel = modelID
            isAuto = false
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName(for: modelID))
                        .typography(Typography.navTab)
                        .foregroundStyle(colors.text.standard.base)

                    if let subtitle = subtitle(for: modelID) {
                        Text(subtitle)
                            .typography(Typography.miniLabel)
                            .foregroundStyle(colors.text.standard.muted)
                    }
                }

                Spacer()

                if !isAuto, selectedModel == modelID {
                    Image(systemName: "checkmark")
                        .foregroundStyle(colors.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
        guard !searchText.isEmpty else { return true }
        let query = searchText.lowercased()
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
