import Factory
import SwiftUI

/// Single-select model picker for power-user override.
///
/// Shows the auto-selected model prominently at the top, followed by
/// "Recommended" (ordered by preference ranking) and "Other" sections.
struct ModelPicker: View {
    let providerName: String
    let availableModels: [String]
    @Binding var selectedModel: String

    @Environment(\.colors) private var colors
    @Environment(\.dismiss) private var dismiss
    @Injected(\.modelMetadataService) private var modelMetadataService

    @State private var searchText = ""
    @State private var metadata: [String: ModelMetadata] = [:]
    @State private var isLoaded = false
    @State private var isOtherCollapsed = true

    private var autoSelectedModel: String? {
        KnownModelCatalog.bestModel(from: availableModels)
    }

    // MARK: - Filtering & Grouping

    private var knownModels: [String] {
        let base = availableModels.filter { metadata[$0] != nil }
        return applySearch(base)
    }

    private var unknownModels: [String] {
        let base = availableModels.filter { metadata[$0] == nil }
        return applySearch(base)
    }

    /// Known models sorted by preference ranking, excluding the auto-selected model.
    private var rankedModels: [String] {
        knownModels
            .filter { $0 != autoSelectedModel }
            .sorted { rankIndex($0) < rankIndex($1) }
    }

    private func rankIndex(_ modelID: String) -> Int {
        if let idx = KnownModelCatalog.preferenceRanking.firstIndex(where: { pattern in
            KnownModelCatalog.lookup(modelID)?.pattern == pattern
        }) {
            return idx
        }
        return Int.max
    }

    private func applySearch(_ models: [String]) -> [String] {
        guard !searchText.isEmpty else { return models }
        let query = searchText.lowercased()
        return models.filter { id in
            displayName(for: id).lowercased().contains(query)
                || id.lowercased().contains(query)
        }
    }

    // MARK: - Body

    var body: some View {
        List {
            // Auto-selected model — elevated at the top
            if let auto = autoSelectedModel, searchText.isEmpty {
                Section {
                    Button {
                        selectedModel = auto
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(displayName(for: auto))
                                    .font(Typography.headline)
                                    .foregroundStyle(colors.textPrimary)

                                HStack(spacing: Spacing.xs) {
                                    Text(Localized.Provider.recommendedForYou)
                                        .font(Typography.caption)
                                        .foregroundStyle(colors.accent)

                                    if let sub = subtitle(for: auto) {
                                        Text(verbatim: "·")
                                            .font(Typography.caption)
                                            .foregroundStyle(colors.textSecondary)
                                        Text(sub)
                                            .font(Typography.caption)
                                            .foregroundStyle(colors.textSecondary)
                                    }
                                }
                            }

                            Spacer()

                            if selectedModel == auto {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(colors.accent)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            if !rankedModels.isEmpty {
                Section("Other Recommended") {
                    ForEach(rankedModels, id: \.self) { modelID in
                        modelRow(modelID)
                    }
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
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: isOtherCollapsed ? "chevron.right" : "chevron.down")
                                .font(Typography.caption)
                                .foregroundStyle(colors.textSecondary)
                            Text(Localized.Model.Picker.allModels)
                            Text(verbatim: "\(unknownModels.count)")
                                .font(Typography.caption)
                                .foregroundStyle(colors.textSecondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            if rankedModels.isEmpty, unknownModels.isEmpty, autoSelectedModel == nil {
                Section {
                    HStack(alignment: .top, spacing: Spacing.sm) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(colors.textSecondary)
                            .font(Typography.caption)
                        Text(Localized.Model.Picker.noSearchResults)
                            .font(Typography.caption)
                            .foregroundStyle(colors.textSecondary)
                    }
                    .padding(.vertical, Spacing.xs)
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search models")
        .opacity(isLoaded ? 1 : 0)
        .animation(.easeIn(duration: 0.25), value: isLoaded)
        .scrollContentBackground(.hidden)
        .background(colors.background.ignoresSafeArea())
        .navigationTitle("Choose Model")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let enriched = await modelMetadataService.enrich(
                modelIDs: availableModels,
                provider: providerName
            )
            metadata = Dictionary(
                enriched.map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            isLoaded = true
        }
    }

    // MARK: - Model Row

    private func modelRow(_ modelID: String) -> some View {
        Button {
            selectedModel = modelID
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName(for: modelID))
                        .font(Typography.body)
                        .foregroundStyle(colors.textPrimary)

                    if let subtitle = subtitle(for: modelID) {
                        Text(subtitle)
                            .font(Typography.caption)
                            .foregroundStyle(colors.textSecondary)
                    }
                }

                Spacer()

                if selectedModel == modelID {
                    Image(systemName: "checkmark")
                        .foregroundStyle(colors.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
