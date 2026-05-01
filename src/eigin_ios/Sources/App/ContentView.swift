import Factory
import SwiftData
import SwiftUI

/// Root view with three tabs: Chats, Agent, and Settings.
struct ContentView: View {
    @Environment(\.themeManager) private var themeManager
    @Injected(\.languageManager) private var languageManager
    @Environment(\.colors) private var colors
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(PendingInitiative.userDefaultsKey) private var pendingInitiativeID: String?
    private enum TabItem: String {
        case chats, agent, settings
    }

    @State private var selectedTab = TabItem.chats

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab(Localized.Ui.chats, systemImage: "bubble", value: TabItem.chats) {
                ChatListView()
            }
            Tab(Localized.Ui.agent, systemImage: "person.crop.circle", value: TabItem.agent) {
                AgentView()
            }
            Tab(Localized.Ui.settings, systemImage: "gearshape", value: TabItem.settings) {
                SettingsView()
            }
        }
        .tint(colors.accent)
        .id("\(themeManager.currentTheme.id)-\(languageManager.currentLanguage.rawValue)")
        .onChange(of: pendingInitiativeID) { _, newValue in
            if newValue != nil {
                selectedTab = .chats
            }
        }
        .task {
            ensureBackgroundSchedule()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                ensureBackgroundSchedule()
            }
        }
    }

    private func ensureBackgroundSchedule() {
        let descriptor = FetchDescriptor<Agent>(
            predicate: #Predicate { $0.bootstrapComplete },
            sortBy: [SortDescriptor(\Agent.updatedAt, order: .reverse)]
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
