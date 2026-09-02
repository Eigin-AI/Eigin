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
                    agentCard
                    if let asset = upgradeAsset {
                        voiceUpgradeCard(asset: asset)
                    }
                    providerCard
                }
                .padding(.horizontal, Spacing.n16)
                .padding(.top, Spacing.n8)
                .padding(.bottom, Spacing.n32)
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
                description: asset.downloadDescription,
                detents: [.medium],
                fitsContent: true
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

    // MARK: - Agent Card (presentation + initiative + advanced)

    private var agentCard: some View {
        AppCardSurface(padding: 0) {
            VStack(spacing: 0) {
                // Presentation row
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
                .padding(.horizontal, Spacing.n24)
                .padding(.vertical, Spacing.n16)

                Divider().padding(.leading, Spacing.n24)

                // Voice row
                AppOptionPicker(
                    title: Localized.Agent.Profile.voice,
                    options: voiceOptions,
                    selection: selectedVoiceID
                ) { newValue in
                    agent.voiceIdentifier = newValue.isEmpty ? nil : newValue
                }

                Divider().padding(.leading, Spacing.n24)

                // Initiative row
                AppOptionPicker(
                    title: Localized.Agent.Profile.Section.initiative,
                    description: agent.proactivity.description,
                    options: ProactivityLevel.allCases.map {
                        AppOption($0.displayName, value: $0)
                    },
                    selection: agent.proactivity
                ) { agent.proactivity = $0 }

                Divider().padding(.leading, Spacing.n24)

                // Advanced row
                NavigationLink {
                    AgentAdvanced(agent: agent)
                        .hidesTabBar()
                } label: {
                    HStack(spacing: Spacing.n16) {
                        Text(Localized.Agent.Profile.Section.advanced)
                            .typography(Typography.titleXS)
                            .foregroundStyle(colors.text.standard.base)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .typography(Typography.miniLabel)
                            .foregroundStyle(colors.text.standard.muted)
                    }
                    .padding(.horizontal, Spacing.n24)
                    .padding(.vertical, Spacing.n16)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Voice Upgrade Card

    /// The upgrade offer lives entirely in the shared row: the name plus the
    /// install affordance says enough.
    private func voiceUpgradeCard(asset: any OnDemandAsset) -> some View {
        AssetRow(asset: asset)
    }

    // MARK: - Provider Card (provider picker + model row)

    private var providerCard: some View {
        VStack(spacing: Sizing.PageLayout.ContentGrouping.gap) {
            sectionLabel(Localized.Provider.modelLabel)

            AppCardSurface(padding: 0) {
                VStack(spacing: 0) {
                    AppOptionPicker(
                        title: Localized.Ui.provider,
                        options: providers.map { AppOption($0.name, value: $0.id) },
                        selection: agent.providerID
                    ) { providerBinding.wrappedValue = $0 }

                    if currentProvider != nil {
                        Divider().padding(.horizontal, Spacing.n24)

                        NavigationLink {
                            if let provider = currentProvider {
                                ModelPicker(
                                    provider: provider,
                                    selectedModel: $agent.model,
                                    isAuto: $agent.autoModel
                                )
                                .hidesTabBar()
                            }
                        } label: {
                            HStack(spacing: Spacing.n16) {
                                Text(Localized.Provider.modelLabel)
                                    .typography(Typography.titleXS)
                                    .foregroundStyle(colors.text.standard.base)
                                Spacer()
                                Text(
                                    agent.autoModel
                                        ? Localized.Model.Picker.Auto.title
                                        : modelDisplayName(agent.model)
                                )
                                .typography(Typography.tag)
                                .foregroundStyle(colors.text.standard.muted)
                                .lineLimit(1)
                                Image(systemName: "chevron.right")
                                    .typography(Typography.miniLabel)
                                    .foregroundStyle(colors.text.standard.muted)
                            }
                            .padding(.horizontal, Spacing.n24)
                            .padding(.vertical, Spacing.n16)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .typography(Typography.miniLabel)
            .foregroundStyle(colors.text.standard.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.n8)
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
                // A model pinned on the old provider means nothing on the new one, so
                // seed a sensible starting point and let the router take it from there.
                agent.autoModel = true
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
