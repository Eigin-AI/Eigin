import Factory
import SwiftData
import SwiftUI

/// The screen for a provider you connected yourself, whichever way you got in.
///
/// A key and a sign-in differ in one fact row and in what the screen offers
/// when they break, so they are one screen rather than two. Models carry no
/// description: the provider does not give us one worth printing, and
/// inventing a line per model would be worse than the name alone. Replaces the
/// old edit screen — new connections keep working through
/// ``ProviderConnectSheetContent``, and a key is replaced here.
struct AiProviderScreen: View {
    @Environment(\.colors) private var colors
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Injected(\.keychainService) private var keychainService

    @Bindable var provider: Provider

    @Injected(\.modelMetadataService) private var modelMetadataService

    @State private var apiKey = ""
    @State private var isReplacingKey = false
    @State private var isConnecting = false
    @State private var connectionError: ConnectionError?
    @State private var showRemoveConfirmation = false
    @State private var metadata: [String: ModelMetadata] = [:]

    private var preset: ProviderPreset? {
        ProviderPreset.all.first { $0.baseURL == provider.baseURL }
    }

    private var connectsVia: String {
        preset?.authMethod == .oAuthPKCE || preset?.authMethod == .chatGPTSubscription
            ? Localized.Provider.Connect.viaSignIn
            : Localized.Provider.Connect.viaApiKey
    }

    /// ChatGPT subscription sign-in carries a refreshable credential, not a
    /// static key — nothing to mask, and replacement means signing in again.
    private var isChatGPTProvider: Bool {
        ProviderPreset.isChatGPTSubscription(provider.baseURL)
    }

    var body: some View {
        VStack(spacing: 0) {
            AppNavigationHeader(
                title: provider.name,
                leading: {
                    AppActionButton(
                        icon: Iconography.Functional.Arrow.left,
                        variant: .open,
                        size: .medium,
                        action: { dismiss() }
                    )
                },
                trailing: {
                    if isConnecting {
                        ProgressView()
                            .padding(.trailing, Spacing.n4)
                    }
                }
            )

            ScrollView {
                VStack(spacing: Sizing.PageLayout.gap) {
                    AppIdentityHeader(
                        name: provider.name,
                        kind: Localized.Provider.AiScreen.kindLabel,
                        state: connectionState,
                        status: statusLabel,
                        icon: providerMark(),
                        letter: providerMark() == nil ? String(provider.name.prefix(1)) : nil
                    )

                    if let error = connectionError {
                        AppNotice(
                            tone: .warning,
                            title: error.title,
                            body: error.suggestion
                        )
                    }

                    if isConnecting {
                        connectingNotice
                    }

                    facts

                    if isChatGPTProvider {
                        signInRefresh
                    }

                    if isReplacingKey {
                        keyReplacement
                    }

                    models

                    remove
                }
                .padding(.horizontal, Spacing.n16)
                .padding(.top, Spacing.n8)
                .padding(.bottom, Spacing.n32)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(colors.surface.standard.base.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task { await enrichModels() }
        .onAppear {
            apiKey = keychainService
                .read(key: keychainService.providerKey(for: provider.id)) ?? ""
        }
        .alert(
            Localized.Provider.AiScreen.removeTitle(provider.name),
            isPresented: $showRemoveConfirmation
        ) {
            Button(Localized.Ui.remove, role: .destructive) { removeProvider() }
            Button(Localized.Common.Actions.cancel, role: .cancel) {}
        } message: {
            Text(Localized.Provider.Edit.removeWarning)
        }
        .sheet(item: $signInAgainAuth, onDismiss: {
            signInAgainTask?.cancel()
        }) { auth in
            SafariView(url: auth.url)
        }
    }

    // MARK: - Header state

    /// Nothing claims broken without evidence: a health claim says so only
    /// when a check has failed.
    private var connectionState: ConnectionState {
        connectionError != nil ? .attention : .connected
    }

    private var statusLabel: String {
        connectionError != nil
            ? Localized.Provider.AiScreen.Status.notWorking
            : Localized.Provider.AiScreen.Status.connected
    }

    /// A rejected credential is ours to replace, so the screen carries the
    /// button that answers the notice.
    private var connectingNotice: some View {
        AppCardSurface {
            HStack(spacing: Spacing.n8) {
                ProgressView()
                Text(Localized.Provider.AiScreen.checkingConnection)
                    .typography(Typography.tag)
                    .foregroundStyle(colors.text.standard.muted)
            }
        }
    }

    // MARK: - Facts

    private var facts: some View {
        AppRowsGroup(
            rows: [
                AppRowSpec(
                    title: Localized.Provider.AiScreen.Facts.connectsVia,
                    value: connectsVia,
                    accessory: .none
                ),
            ] + (isChatGPTProvider ? [] : [
                AppRowSpec(
                    title: Localized.Provider.AiScreen.Facts.key,
                    value: maskedKey,
                    accessory: .none
                ),
            ])
        )
    }

    // MARK: - Sign-in refresh (ChatGPT)

    @State private var signInAgainAuth: ChatGPTAuthPresentation?
    @State private var signInAgainTask: Task<Void, Never>?

    /// Reruns the sign-in to replace a dead or rejected credential.
    private var signInRefresh: some View {
        AppRowsGroup(
            rows: [
                AppRowSpec(
                    title: Localized.Provider.AiScreen.signInAgain,
                    accessory: .chevron,
                    action: { reconnectChatGPT() }
                ),
            ]
        )
    }

    private var maskedKey: String {
        guard apiKey.count > 8 else {
            return String(repeating: "•", count: max(apiKey.count, 4))
        }
        return "\(apiKey.prefix(4))••••\(apiKey.suffix(4))"
    }

    // MARK: - Key replacement

    private var keyReplacement: some View {
        VStack(spacing: Sizing.PageLayout.ContentGrouping.gap) {
            AppTextInput(
                label: Localized.Common.Fields.apiKey,
                text: $apiKey,
                isError: connectionError != nil,
                errorMessage: connectionError?.title ?? "",
                isSecure: true
            )

            AppButton(
                Localized.Provider.AiScreen.saveKey,
                variant: .primary,
                action: { reconnect() }
            )
            .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    // MARK: - Models

    /// Three models, and a way to the rest, where they can be searched.
    private var models: some View {
        AppContentGroup(
            label: Localized.Provider.AiScreen.modelsLabel,
            footnote: modelsFootnote
        ) {
            ForEach(Array(shownModels.enumerated()), id: \.element) { index, modelID in
                if index > 0 { RowHairline() }
                AppRow(
                    AppRowSpec(
                        id: modelID,
                        title: displayName(for: modelID),
                        trailing: .toggle(
                            isOn: provider.enabledModels.contains(modelID),
                            isDisabled: false,
                            action: { toggleModel(modelID) }
                        )
                    )
                )
            }
            if provider.availableModels.count > shownModels.count {
                RowHairline()
                NavigationLink {
                    ProviderModelsScreen(provider: provider)
                        .hidesTabBar()
                } label: {
                    AppRow(
                        AppRowSpec(
                            title: Localized.Provider.AiScreen.showAllModels(
                                "\(provider.availableModels.count)"
                            ),
                            tone: .muted
                        )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// The first trio the catalogue would reach for; the search screen has
    /// the rest, where everything can be searched.
    private var shownModels: [String] {
        var seen = Set<String>()
        let all = provider.availableModels.filter { seen.insert($0).inserted }
        let known = all.filter { metadata[$0] != nil }
        let unknown = all.filter { metadata[$0] == nil }

        let patternIndex = Dictionary(
            uniqueKeysWithValues: KnownModelCatalog.preferenceRanking.enumerated()
                .map { ($0.element, $0.offset) }
        )
        let top = known.sorted {
            rank(of: $0, by: patternIndex) < rank(of: $1, by: patternIndex)
        }
        return Array((top + unknown).prefix(3))
    }

    private func rank(of id: String, by patternIndex: [String: Int]) -> Int {
        guard let pattern = KnownModelCatalog.lookup(id)?.pattern,
              let rank = patternIndex[pattern]
        else { return .max }
        return rank
    }

    private var modelsFootnote: String {
        if provider.enabledModels.isEmpty {
            return Localized.Provider.AiScreen.modelsFootnoteNone(provider.name)
        }
        return Localized.Provider.AiScreen.modelsFootnote(
            "\(provider.enabledModels.count)",
            "\(provider.availableModels.count)"
        )
    }

    private func toggleModel(_ modelID: String) {
        if let index = provider.enabledModels.firstIndex(of: modelID) {
            provider.enabledModels.remove(at: index)
        } else {
            provider.enabledModels.append(modelID)
        }
        Haptics.light()
        // A disabled model may be the one a running agent is on; force-resolve now.
        Task { await AgentAutoRouting.forceResolveAgents(on: provider) }
    }

    // MARK: - Remove

    private var remove: some View {
        AppRowsGroup(
            rows: [
                AppRowSpec(
                    title: Localized.Provider.AiScreen.remove(provider.name),
                    accessory: .trash,
                    tone: .destructive,
                    action: { showRemoveConfirmation = true }
                ),
            ]
        )
    }

    // MARK: - Mark

    private func enrichModels() async {
        let enriched = await modelMetadataService.enrich(
            modelIDs: provider.availableModels,
            provider: provider.name
        )
        metadata = Dictionary(
            enriched.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private func displayName(for modelID: String) -> String {
        guard let meta = metadata[modelID], meta.name != modelID else { return modelID }
        if let tag = meta.versionTag {
            return "\(meta.name) (\(tag))"
        }
        return meta.name
    }

    private func providerMark() -> Image? {
        guard let preset else { return nil }
        return preset.logo.map(Image.init(uiImage:))
    }

    // MARK: - Actions

    /// The old edit screen's validation, kept once the new key is in hand.
    private func reconnect() {
        isConnecting = true
        connectionError = nil

        Task {
            do {
                let client = LLMClientFactory.client(
                    baseURL: provider.baseURL,
                    apiToken: apiKey
                )
                let modelIDs = try await client.fetchModels()
                if let firstModel = modelIDs.first {
                    try await client.validateAPIKey(model: firstModel)
                }

                // Model enablements survive the key change where the models do.
                provider.availableModels = modelIDs
                provider.enabledModels = provider.enabledModels.filter { modelIDs.contains($0) }
                provider.updatedAt = .now
                keychainService.save(
                    key: keychainService.providerKey(for: provider.id),
                    value: apiKey
                )

                isConnecting = false
                isReplacingKey = false
                Haptics.success()
            } catch {
                connectionError = ConnectionError(from: error)
                isConnecting = false
                Haptics.error()
            }
        }
    }

    private func removeProvider() {
        keychainService.delete(key: keychainService.providerKey(for: provider.id))
        if isChatGPTProvider {
            Task { await chatGPTCredentialStore.clear(providerID: provider.id) }
        }
        modelContext.delete(provider)
        dismiss()
    }

    // MARK: - ChatGPT reauthorization

    @Injected(\.chatGPTCredentialStore) private var chatGPTCredentialStore

    /// Reruns the ChatGPT sign-in, verifies the fresh credential, and replaces
    /// the stored one — the sign-in group's answer to an expired or revoked
    /// subscription connection. Dismissing the browser sheet cancels the wait.
    private func reconnectChatGPT() {
        isConnecting = true
        connectionError = nil

        signInAgainTask = Task {
            do {
                let service = DefaultChatGPTSignInService(credentialStore: chatGPTCredentialStore)
                let clientID = await chatGPTCredentialStore.clientID(providerID: provider.id)
                let idToken = await chatGPTCredentialStore.idToken(providerID: provider.id)
                let credential = try await service.authenticate(
                    existingClientID: clientID,
                    idTokenHint: idToken
                ) { url in
                    signInAgainAuth = ChatGPTAuthPresentation(url: url)
                }
                signInAgainTask = nil
                signInAgainAuth = nil

                let client = ResponsesAPIClient(apiToken: credential.accessToken)
                let modelIDs = try await client.fetchModels()

                // Enablements survive the sign-in where models do.
                provider.availableModels = modelIDs
                provider.enabledModels = provider.enabledModels.filter { modelIDs.contains($0) }
                provider.updatedAt = .now
                await chatGPTCredentialStore.save(credential, providerID: provider.id)

                isConnecting = false
                Haptics.success()
            } catch ChatGPTSubscriptionError.userCancelled, is CancellationError {
                signInAgainTask = nil
                signInAgainAuth = nil
                isConnecting = false
            } catch {
                signInAgainTask = nil
                signInAgainAuth = nil
                connectionError = ConnectionError(from: error)
                isConnecting = false
                Haptics.error()
            }
        }
    }
}

#Preview {
    NavigationStack { Text("Placeholder") }
}
