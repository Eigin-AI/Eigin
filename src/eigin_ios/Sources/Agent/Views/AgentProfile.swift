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
    @State private var showVoicePicker = false
    @State private var showOtherVoices = false
    @State private var showDownloadPrompt = false
    @State private var showEmojiPicker = false
    @State private var isEditingName = false
    @State private var editingNameText = ""
    @FocusState private var isNameFocused: Bool

    private var currentProvider: Provider? {
        providers.first { $0.id == agent.providerID }
    }

    private var availableModels: [String] {
        currentProvider?.availableModels ?? []
    }

    private var availableVoices: [SpeechVoice] {
        voiceService.availableSpeechVoices(for: languageManager.currentLanguage)
    }

    private var currentVoiceName: String {
        let id = agent.voiceIdentifier ?? ""
        if id.isEmpty { return Localized.Chat.systemDefault }
        if let match = availableVoices.first(where: { $0.identifier == id }) {
            return match.displayName
        }
        return Localized.Chat.systemDefault
    }

    private var upgradeAsset: (any OnDemandAsset)? {
        voiceService.upgradeAsset(for: languageManager.currentLanguage)
    }

    var body: some View {
        Form {
            presentationSection
            proactivitySection
            coreSection
            providerSection
        }
        .scrollContentBackground(.hidden)
        .onChange(of: agent.name) { agent.updatedAt = .now }
        .onChange(of: agent.emoji) { agent.updatedAt = .now }
        .onChange(of: agent.providerID) { agent.updatedAt = .now }
        .onChange(of: agent.model) { agent.updatedAt = .now }
        .onChange(of: agent.identityCore) { agent.updatedAt = .now }
        .onChange(of: agent.userCore) { agent.updatedAt = .now }
        .onChange(of: agent.soulCore) { agent.updatedAt = .now }
        .onChange(of: agent.voiceIdentifier) { agent.updatedAt = .now }
        .onChange(of: languageManager.currentLanguage) {
            // Reset voice to system default when the language changes,
            // since the available voices may differ across engines/locales.
            agent.voiceIdentifier = nil
        }
        .sheet(isPresented: $showDownloadPrompt) {
            if let asset = upgradeAsset {
                AssetDownloadPrompt(
                    asset: asset,
                    onAccept: { showDownloadPrompt = false },
                    onDecline: { showDownloadPrompt = false }
                )
                .presentationDetents([.medium])
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
    }

    // MARK: - Presentation

    private var presentationSection: some View {
        Section {
            Group {
                HStack(alignment: .center, spacing: Spacing.sm) {
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
                            .typography(Typography.title)
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
                            .typography(Typography.title)
                            .foregroundStyle(colors.textPrimary)
                            .onTapGesture {
                                editingNameText = agent.name
                                withAnimation(Animations.snap) {
                                    isEditingName = true
                                }
                            }
                    }

                    Spacer()
                }

                DisclosureGroup(isExpanded: $showVoicePicker) {
                    voiceRow(
                        label: Localized.Chat.systemDefault,
                        voice: nil
                    )

                    let voices = availableVoices
                    ForEach(voices) { voice in
                        voiceRow(label: voice.displayName, subtitle: voice.dialect, voice: voice)
                    }

                } label: {
                    HStack(spacing: Spacing.sm) {
                        SettingsIcon(systemName: "waveform", color: .purple)
                        Text(Localized.Agent.Profile.voice)
                            .typography(Typography.subheadline)
                            .foregroundStyle(colors.textPrimary)
                        Spacer()
                        Text(currentVoiceName)
                            .foregroundStyle(colors.textSecondary)
                            .typography(Typography.callout)
                    }
                }

                if let asset = upgradeAsset {
                    if case .downloading(let progress) = asset.state {
                        HStack(spacing: Spacing.sm) {
                            CircularProgressView(progress: progress)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(asset.displayName)
                                    .typography(Typography.subheadline)
                                    .foregroundStyle(colors.textPrimary)
                                Text(Localized.Status.downloading)
                                    .typography(Typography.caption)
                                    .foregroundStyle(colors.textSecondary)
                            }
                        }
                    } else {
                        Button {
                            showDownloadPrompt = true
                        } label: {
                            HStack(spacing: Spacing.sm) {
                                Image(systemName: "arrow.down.circle")
                                    .foregroundStyle(colors.accent)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(asset.displayName)
                                        .typography(Typography.subheadline)
                                        .foregroundStyle(colors.textPrimary)
                                    Text(asset.downloadDescription)
                                        .typography(Typography.caption)
                                        .foregroundStyle(colors.textSecondary)
                                }
                            }
                        }
                    }
                }
            }
            .listRowBackground(colors.surface)
        } header: {
            Text(Localized.Agent.Profile.Section.presentation)
                .typography(Typography.label)
        } footer: {
            if showVoicePicker {
                if !voiceService.isUsingEnhancedEngine(for: languageManager.currentLanguage) {
                    Text(Localized.Agent.Profile.Voice.installHint)
                }
            }
        }
    }

    // MARK: - Provider

    private var providerSection: some View {
        Section {
            Group {
                HStack(spacing: Spacing.sm) {
                    SettingsIcon(systemName: "server.rack", color: .blue)
                    Picker(Localized.Ui.provider, selection: providerBinding) {
                        ForEach(providers) { provider in
                            Text(provider.name)
                                .typography(Typography.body)
                                .tag(provider.id)
                        }
                    }
                }
                NavigationLink {
                    ModelPicker(
                        providerName: currentProvider?.name ?? "",
                        availableModels: availableModels,
                        selectedModel: $agent.model
                    )
                } label: {
                    HStack(spacing: Spacing.sm) {
                        SettingsIcon(systemName: "cpu", color: .teal)
                        Text(Localized.Provider.modelLabel)
                            .typography(Typography.subheadline)
                            .foregroundStyle(colors.textPrimary)
                        Spacer()
                        Text(modelDisplayName(agent.model))
                            .foregroundStyle(colors.textSecondary)
                            .typography(Typography.callout)
                    }
                }
            }
            .listRowBackground(colors.surface)
        } header: {
            Text(Localized.Provider.modelLabel)
                .typography(Typography.label)
        }
    }

    // MARK: - Core

    private var coreSection: some View {
        Section {
            Group {
                coreDocumentRow(
                    title: Localized.Agent.identityLabel,
                    icon: "person.text.rectangle",
                    color: .orange,
                    text: $agent.identityCore
                )
                coreDocumentRow(
                    title: Localized.Agent.userLabel,
                    icon: "person.fill",
                    color: .green,
                    text: $agent.userCore
                )
                coreDocumentRow(
                    title: Localized.Agent.soul,
                    icon: "sparkles",
                    color: .indigo,
                    text: $agent.soulCore
                )

                NavigationLink {
                    KnowledgeContainer(agentID: agent.id)
                } label: {
                    HStack(spacing: Spacing.sm) {
                        SettingsIcon(systemName: "book.closed", color: .cyan)
                        Text(Localized.Knowledge.sectionTitle)
                            .typography(Typography.subheadline)
                            .foregroundStyle(colors.textPrimary)
                    }
                }

                NavigationLink {
                    IntentsList(agentID: agent.id)
                } label: {
                    HStack(spacing: Spacing.sm) {
                        SettingsIcon(systemName: "arrow.triangle.branch", color: .orange)
                        Text(Localized.Agent.intents)
                            .typography(Typography.subheadline)
                            .foregroundStyle(colors.textPrimary)
                    }
                }

                NavigationLink {
                    SkillsList()
                } label: {
                    HStack(spacing: Spacing.sm) {
                        SettingsIcon(systemName: "sparkles.rectangle.stack", color: .purple)
                        Text(Localized.Agent.skills)
                            .typography(Typography.subheadline)
                            .foregroundStyle(colors.textPrimary)
                    }
                }
            }
            .listRowBackground(colors.surface)
        } header: {
            Text(Localized.Agent.Profile.Section.core)
                .typography(Typography.label)
        }
    }

    private func coreDocumentRow(
        title: String,
        icon: String,
        color: Color,
        text: Binding<String>
    ) -> some View {
        NavigationLink {
            DocumentEditor(title: title, text: text)
        } label: {
            HStack(spacing: Spacing.sm) {
                SettingsIcon(systemName: icon, color: color)
                Text(title)
                    .typography(Typography.subheadline)
                    .foregroundStyle(colors.textPrimary)
                Spacer()
                Text(text.wrappedValue
                    .isEmpty ? Localized.Common.Placeholder
                    .notSet : String(text.wrappedValue.prefix(30)) + "...")
                    .foregroundStyle(colors.textSecondary)
                    .typography(Typography.callout)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Proactivity

    private var proactivitySection: some View {
        Section {
            Group {
                Picker("Proactivity", selection: $agent.proactivity) {
                    ForEach(ProactivityLevel.allCases, id: \.self) { level in
                        Label(level.displayName, systemImage: level.systemImage)
                            .tag(level)
                    }
                }
                .pickerStyle(.segmented)

                HStack(spacing: Spacing.sm) {
                    Image(systemName: agent.proactivity.systemImage)
                        .foregroundStyle(colors.accent)
                        .frame(width: 20)
                    Text(agent.proactivity.description)
                        .typography(Typography.caption)
                        .foregroundStyle(colors.textSecondary)
                }
            }
            .listRowBackground(colors.surface)
        } header: {
            Text(Localized.Agent.Profile.Section.initiative)
                .typography(Typography.label)
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

    private func voiceRow(
        label: String,
        subtitle: String? = nil,
        voice: SpeechVoice?
    ) -> some View {
        Button {
            agent.voiceIdentifier = voice?.identifier
        } label: {
            HStack {
                Text(label)
                    .typography(Typography.body)
                    .foregroundStyle(colors.textPrimary)
                if let subtitle {
                    Spacer()
                    Text(subtitle)
                        .typography(Typography.callout)
                        .foregroundStyle(colors.textSecondary)
                }
                Spacer()
                if (agent.voiceIdentifier ?? "") == (voice?.identifier ?? "") {
                    Image(systemName: "checkmark")
                        .foregroundStyle(colors.accent)
                }
            }
        }
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
