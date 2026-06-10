import Factory
import SwiftData
import SwiftUI

/// Root view with three tabs: Chats, Agent, and Settings.
struct ContentView: View {
    @Environment(\.themeManager) private var themeManager
    @Injected(\.languageManager) private var languageManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(PendingInitiative.userDefaultsKey) private var pendingInitiativeID: String?
    @State private var selectedTab = RootTab.chats

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
        .onChange(of: pendingInitiativeID) { _, newValue in
            if newValue != nil {
                selectedTab = .chats
            }
        }
        .task {
            ensureBackgroundSchedule()
            GemmaModelManager.shared.prewarmIfNeeded()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                ensureBackgroundSchedule()
                GemmaModelManager.shared.prewarmIfNeeded()
            }
            if phase == .background {
                // Cancel prewarm: ANE compilation under the background memory
                // limit risks jetsam. The pass resumes on next foreground.
                GemmaModelManager.shared.cancelPrewarm()
            }
        }
    }

    private func ensureBackgroundSchedule() {
        let descriptor = FetchDescriptor<Agent>(
            predicate: #Predicate { $0.bootstrapComplete },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        guard let agents = try? modelContext.fetch(descriptor),
              // TODO: Use the primary agent once that concept is formalized.
              let agent = agents.first,
              agent.proactivity.isBackgroundEnabled
        else {
            return
        }
        Task {
            await BackgroundPromptScheduler.scheduleIfNeeded(for: agent.proactivity)
        }
    }
}

#Preview {
    ContentView()
        .previewEnvironment()
}
