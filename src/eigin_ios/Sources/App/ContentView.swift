import _AppIntents_SwiftUI
import Factory
import SwiftData
import SwiftUI

/// Root view with three tabs: Chats, Agent, and Settings.
struct ContentView: View {
    @Environment(\.themeManager) private var themeManager
    @Injected(\.languageManager) private var languageManager
    @Injected(\.relayClient) private var relayClient
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(PendingDestination.storageKey) private var pendingDestination: String?
    @State private var selectedTab = RootTab.chats
    @Bindable private var gemmaManager = GemmaModelManager.shared

    var body: some View {
        ZStack {
            switch selectedTab {
            case .chats:
                ChatListView()
            case .agent:
                AgentView()
            case .settings:
                SettingsView()
            }

            NavigationBarView(selectedTab: $selectedTab)
        }
        .id("\(themeManager.currentTheme.id)-\(languageManager.currentLanguage.rawValue)")
        .onChange(of: selectedTab) {
            TabBarVisibility.shared.popAll()
        }
        // The system runs the matching closure in-app shortly before the app
        // is foregrounded. ContentView hands the route to the shared pending
        // store; ChatListView navigates when it becomes visible.
        .onAppIntentExecution(NewChatIntent.self) { _ in
            PendingDestination.set(.newChat(.newChat))
        }
        .onAppIntentExecution(DictationChatIntent.self) { _ in
            PendingDestination.set(.newChat(.dictationChat))
        }
        .onAppIntentExecution(LiveCallChatIntent.self) { _ in
            PendingDestination.set(.newChat(.liveCallChat))
        }
        .onAppIntentExecution(PhotoChatIntent.self) { _ in
            PendingDestination.set(.newChat(.photoChat))
        }
        .onChange(of: pendingDestination) { _, newValue in
            if newValue != nil {
                selectedTab = .chats
            }
        }
        .task {
            ensureBackgroundSchedule()
            ensureEiginProvider()
            ensureLocalProvider()
            GemmaModelManager.shared.prepareIfNeeded()
        }
        .onChange(of: gemmaManager.state) { _, newState in
            if newState == .ready || newState == .downloaded {
                ensureLocalProvider()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                ensureBackgroundSchedule()
                ensureLocalProvider()
            }
        }
    }

    private func ensureBackgroundSchedule() {
        guard let agents = try? modelContext.fetch(Agent.primaryDescriptor),
              let agent = agents.primary,
              agent.proactivity.isBackgroundEnabled
        else {
            return
        }
        Task {
            await BackgroundPromptScheduler.scheduleIfNeeded(for: agent.proactivity)
        }
    }

    /// Ensures a local provider record exists once the on-device model is ready.
    ///
    /// Provider creation was previously tied to `LocalProviderView`'s lifecycle, meaning the
    /// provider was never created if the model finished compiling while the user wasn't on that
    /// screen. Running this on every foreground pass closes that gap.
    private func ensureLocalProvider() {
        let state = GemmaModelManager.shared.state
        guard state == .ready || state == .downloaded else { return }
        let providers = (try? modelContext.fetch(FetchDescriptor<Provider>())) ?? []
        guard !providers.contains(where: { ProviderPreset.isLocal($0.baseURL) }) else { return }
        let provider = Provider(name: Localized.Provider.onDevice, baseURL: "local://")
        provider.availableModels = ["gemma-4-e2b"]
        provider.enabledModels = ["gemma-4-e2b"]
        modelContext.insert(provider)
    }

    /// Ensures the always-present Eigin relay provider exists and keeps its curated model list
    /// fresh.
    ///
    /// Mirrors how On-Device is created in code rather than through the add-provider sheet. The
    /// model
    /// catalog is public, so it refreshes on every launch without needing credits.
    private func ensureEiginProvider() {
        let providers = (try? modelContext.fetch(FetchDescriptor<Provider>())) ?? []
        let provider: Provider
        if let existing = providers.first(where: { ProviderPreset.isRelay($0.baseURL) }) {
            provider = existing
        } else {
            provider = Provider(name: "Eigin", baseURL: "eigin-relay://")
            modelContext.insert(provider)
        }
        Task { @MainActor in
            guard let models = try? await relayClient.models(), !models.isEmpty else { return }
            provider.availableModels = models
            // The Eigin relay is the user's own provider, and its models come and go
            // with the relay — there is no per-model toggle for it — so every known
            // served model is always on.
            provider.enabledModels = KnownModelCatalog.knownModels(in: models)
        }
    }
}

#Preview {
    ContentView()
        .previewEnvironment()
}
