import Factory
import SwiftData
import SwiftUI

struct AgentProfile: View {
    @Environment(\.colors) private var colors
    @Injected(\.modelMetadataService) private var modelMetadataService
    @Injected(\.voiceService) private var voiceService
    @Injected(\.languageManager) private var languageManager
    @Injected(\.knowledgeService) private var knowledgeService

    @Bindable var agent: Agent
    let providers: [Provider]
    @State private var modelMetadata: [String: ModelMetadata] = [:]
    @State private var showDownloadPrompt = false
    @State private var showEmojiPicker = false
    @State private var isEditingName = false
    @State private var editingNameText = ""
    @FocusState private var isNameFocused: Bool

    private var currentProvider: Provider? {
        providers.first { $0.id == agent.providerID }
    }

    private var availableVoices: [SpeechVoice] {
        voiceService.availableSpeechVoices(for: languageManager.currentLanguage)
    }

    /// The current voice resolved to a selectable option value, falling back to
    /// the system default (empty string) when the stored voice is unavailable
    /// (for example after a language change).
    private var selectedVoiceID: String {
        let id = agent.voiceIdentifier ?? ""
        if !id.isEmpty, availableVoices.contains(where: { $0.identifier == id }) {
            return id
        }
        return ""
    }

    private var voiceOptions: [AppOption<String>] {
        [AppOption(Localized.Chat.systemDefault, value: "")]
            + availableVoices.map {
                AppOption($0.displayName, value: $0.identifier, detail: $0.dialect)
            }
    }

    private var upgradeAsset: (any OnDemandAsset)? {
        voiceService.upgradeAsset(for: languageManager.currentLanguage)
    }

    var body: some View {
        let base = VStack(spacing: 0) {
            AppNavigationHeader(title: Localized.Ui.agent, leading: { EmptyView() })

            ScrollView {
                VStack(spacing: Sizing.PageLayout.gap) {
                    VStack(spacing: Sizing.PageLayout.ContentGrouping.gap) {
                        presentationCard
                        voiceGroup
                    }
                    providerGroup
                    proactivityCard
                    advancedCard
                }
                .padding(.horizontal, Spacing.n16)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(colors.surface.standard.base.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: agent.name) { agent.updatedAt = .now }
        .onChange(of: agent.emoji) { agent.updatedAt = .now }
        .onChange(of: agent.providerID) { agent.updatedAt = .now }
        .onChange(of: agent.model) { agent.updatedAt = .now }
        .onChange(of: agent.voiceIdentifier) { agent.updatedAt = .now }
        .onChange(of: languageManager.currentLanguage) {
            agent.voiceIdentifier = nil
        }
        .onChange(of: agent.proactivity) { _, newValue in
            agent.updatedAt = .now
            BackgroundPromptScheduler.reschedule(for: newValue)
            if newValue.isBackgroundEnabled {
                Task {
                    _ = await NotificationPermission.requestIfNeeded()
                }
            }
        }
        .task(id: agent.providerID) {
            guard let provider = currentProvider else { return }
            let results = await modelMetadataService.enrich(
                modelIDs: provider.availableModels,
                provider: provider.name
            )
            modelMetadata = Dictionary(
                results.map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            )
        }

        if let asset = upgradeAsset {
            base.appSheet(
                isPresented: $showDownloadPrompt,
                title: asset.displayName,
                detents: [.medium],
                showsDismissButton: false
            ) {
                AssetDownloadSheetContent(
                    asset: asset,
                    onAccept: { showDownloadPrompt = false },
                    onDecline: { showDownloadPrompt = false }
                )
            }
        } else {
            base
        }
    }

    // MARK: - Presentation

    private var presentationCard: some View {
        AppCardSurface {
            HStack(alignment: .center, spacing: Spacing.n12) {
                Button {
                    showEmojiPicker = true
                } label: {
                    Text(agent.emoji)
                        .font(.system(size: 40))
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showEmojiPicker) {
                    EmojiGrid(
                        selectedEmoji: $agent.emoji,
                        isPresented: $showEmojiPicker,
                        colors: colors
                    )
                }

                if isEditingName {
                    TextField(Localized.Common.Fields.agentName, text: $editingNameText)
                        .typography(Typography.titleM)
                        .focused($isNameFocused)
                        .onSubmit { commitNameEdit() }
                        .onChange(of: isNameFocused) { _, focused in
                            if !focused { commitNameEdit() }
                        }
                        .onAppear {
                            editingNameText = agent.name
                            isNameFocused = true
                        }
                } else {
                    Text(agent.name)
                        .typography(Typography.titleM)
                        .foregroundStyle(colors.text.standard.base)
                        .onTapGesture {
                            editingNameText = agent.name
                            withAnimation(Animations.snap) {
                                isEditingName = true
                            }
                        }
                }

                Spacer()
            }
        }
    }

    // MARK: - Voice

    private var voiceGroup: some View {
        VStack(spacing: Sizing.PageLayout.ContentGrouping.gap) {
            AppOptionPicker(
                title: Localized.Agent.Profile.voice,
                options: voiceOptions,
                selection: selectedVoiceID
            ) { newValue in
                agent.voiceIdentifier = newValue.isEmpty ? nil : newValue
            }

            if let asset = upgradeAsset {
                voiceUpgradeCard(asset: asset)
            }
        }
    }

    @ViewBuilder
    private func voiceUpgradeCard(asset: any OnDemandAsset) -> some View {
        if case .downloading(let progress) = asset.state {
            AppCardSurface {
                HStack(spacing: Spacing.n12) {
                    CircularProgressView(progress: progress)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(asset.displayName)
                            .typography(Typography.titleXS)
                            .foregroundStyle(colors.text.standard.base)
                        Text(Localized.Status.downloading)
                            .typography(Typography.tag)
                            .foregroundStyle(colors.text.standard.muted)
                    }
                    Spacer()
                }
            }
        } else {
            AppCardSurface(action: { showDownloadPrompt = true }) {
                HStack(spacing: Spacing.n12) {
                    Image(systemName: "arrow.down.circle")
                        .foregroundStyle(colors.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(asset.displayName)
                            .typography(Typography.titleXS)
                            .foregroundStyle(colors.text.standard.base)
                        Text(asset.downloadDescription)
                            .typography(Typography.tag)
                            .foregroundStyle(colors.text.standard.muted)
                    }
                    Spacer()
                }
            }
        }
    }

    // MARK: - Provider & Model

    private var providerGroup: some View {
        VStack(spacing: Sizing.PageLayout.ContentGrouping.gap) {
            AppOptionPicker(
                title: Localized.Ui.provider,
                options: providers.map { AppOption($0.name, value: $0.id) },
                selection: agent.providerID
            ) { providerBinding.wrappedValue = $0 }

            if currentProvider != nil {
                modelCard
            }
        }
    }

    private var modelCard: some View {
        NavigationLink {
            if let provider = currentProvider {
                ModelPicker(provider: provider, selectedModel: $agent.model)
                    .hidesTabBar()
            }
        } label: {
            AppCardSurface {
                HStack(spacing: Spacing.n16) {
                    Text(Localized.Provider.modelLabel)
                        .typography(Typography.titleXS)
                        .foregroundStyle(colors.text.standard.base)
                    Spacer()
                    Text(modelDisplayName(agent.model))
                        .typography(Typography.tag)
                        .foregroundStyle(colors.text.standard.muted)
                        .lineLimit(1)
                    Image(systemName: "chevron.right")
                        .typography(Typography.miniLabel)
                        .foregroundStyle(colors.text.standard.muted)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Proactivity

    private var proactivityCard: some View {
        AppCardSurface {
            VStack(alignment: .leading, spacing: Spacing.n16) {
                Text(Localized.Agent.Profile.Section.initiative)
                    .typography(Typography.titleXS)
                    .foregroundStyle(colors.text.standard.base)

                AppSegmentedControl(
                    segments: ProactivityLevel.allCases.map {
                        AppSegment($0.displayName, value: $0)
                    },
                    selection: agent.proactivity
                ) { agent.proactivity = $0 }

                HStack(alignment: .center, spacing: Spacing.n8) {
                    Image(systemName: agent.proactivity.systemImage)
                        .foregroundStyle(colors.icon.standard.muted)
                        .frame(width: 16)
                    Text(agent.proactivity.description)
                        .typography(Typography.tag)
                        .foregroundStyle(colors.text.standard.muted)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    // MARK: - Advanced

    private var advancedCard: some View {
        NavigationLink {
            AgentAdvanced(agent: agent)
                .hidesTabBar()
        } label: {
            AppCardSurface {
                HStack(spacing: Spacing.n16) {
                    Text(Localized.Agent.Profile.Section.advanced)
                        .typography(Typography.titleXS)
                        .foregroundStyle(colors.text.standard.base)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .typography(Typography.miniLabel)
                        .foregroundStyle(colors.text.standard.muted)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func commitNameEdit() {
        let trimmed = editingNameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed != agent.name {
            agent.name = trimmed
            Task { await syncAgentActorName(trimmed) }
        }
        withAnimation(Animations.snap) {
            isEditingName = false
        }
    }

    /// Update the agent's actor entity name in the knowledge graph.
    private func syncAgentActorName(_ name: String) async {
        guard let entity = try? await knowledgeService.getEntity(
            type: "actor", id: "agent", spaceID: nil, agentID: agent.id
        ) else { return }

        let updatedFields = entity.fields.map { field -> FirmField in
            if field.name == "name" {
                return FirmField(name: "name", value: .string(value: name))
            }
            return field
        }

        let updated = FirmEntity(
            id: BundledKnowledge.agentActorID,
            entityType: entity.entityType,
            fields: updatedFields
        )
        try? await knowledgeService.addEntity(updated, spaceID: nil, agentID: agent.id, chatID: nil)
    }

    private var providerBinding: Binding<UUID> {
        Binding(
            get: { agent.providerID },
            set: { newID in
                guard newID != agent.providerID else { return }
                agent.providerID = newID
                if let newProvider = providers.first(where: { $0.id == newID }),
                   let bestModel = KnownModelCatalog.bestModel(from: newProvider.availableModels)
                {
                    agent.model = bestModel
                }
            }
        )
    }

    private func modelDisplayName(_ modelID: String) -> String {
        if let meta = modelMetadata[modelID], meta.name != modelID {
            return meta.name
        }
        return modelID
    }
}
