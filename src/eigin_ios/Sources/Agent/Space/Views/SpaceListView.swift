import SwiftData
import SwiftUI

struct SpaceListView: View {
    @Query(sort: \Space.name) private var spaces: [Space]
    @Query private var agents: [Agent]
    @Query(sort: \Chat.updatedAt) private var allChats: [Chat]

    private var agent: Agent? {
        agents.primary
    }

    private var activeProvider: Provider? {
        guard let agent else { return nil }
        return providers.first { $0.id == agent.providerID }
    }

    @Query(sort: \Provider.createdAt) private var providers: [Provider]

    @State private var selectedSpace: Space?
    @State private var showBootstrap = false

    var body: some View {
        AppSecondaryScreen(title: Localized.Space.title, fillsViewport: spaces.isEmpty) {
            if spaces.isEmpty {
                AppEmptyState(
                    icon: Iconography.Brand.security,
                    title: Localized.Space.EmptyState.title,
                    description: Localized.Space.EmptyState.hint
                ) {
                    AppButton(Localized.Space.create, variant: .secondary) { showBootstrap = true }
                        .disabled(agent == nil || activeProvider == nil)
                }
            } else {
                AppContentGroup {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(spaces.enumerated()), id: \.element.id) { index, space in
                            if index > 0 { RowHairline() }
                            let count = Localized.Space.List.chatsCount("\(chatCount(for: space))")
                            AppRow(AppRowSpec(
                                id: space.id.uuidString,
                                title: "\(space.emoji) \(space.name.isEmpty ? Localized.Space.List.untitledSpace : space.name)",
                                description: space
                                    .isPrivate ? "\(Localized.Space.Label.private) · \(count)" :
                                    count,
                                action: { selectedSpace = space }
                            ))
                        }
                    }
                }
            }
        } trailing: {
            AppActionButton(
                icon: Iconography.Functional.plus,
                variant: .open,
                size: .medium,
                action: { showBootstrap = true }
            )
            .accessibilityLabel(Localized.Space.create)
            .disabled(agent == nil || activeProvider == nil)
        }
        .navigationDestination(item: $selectedSpace) { space in
            SpaceDetailView(space: space).hidesTabBar()
        }
        .navigationDestination(isPresented: $showBootstrap) {
            if let agent, let provider = activeProvider {
                SpaceBootstrapView(agent: agent, provider: provider).hidesTabBar()
            }
        }
    }

    private func chatCount(for space: Space) -> Int {
        allChats.count(where: { $0.spaceID == space.id })
    }
}

// MARK: - Preview

#Preview("Spaces") {
    NavigationStack {
        SpaceListView()
    }
    .modelContainer({ () -> ModelContainer in
        let container = try! ModelContainer(
            for: Schema(SchemaV10.models, version: SchemaV10.versionIdentifier),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext

        let provider = Provider(name: "Preview Provider", baseURL: "https://fake.local")
        context.insert(provider)
        let agent = Agent(name: "Eigin", providerID: provider.id, model: "gpt-4o")
        agent.bootstrapComplete = true
        context.insert(agent)

        let samples: [(emoji: String, name: String, chats: Int, isPrivate: Bool)] = [
            ("🚀", "42futures", 2, false),
            ("👨‍🍳", "Chef Coach", 1, false),
            ("🎙️", "Content Interviews and LinkedIn", 7, false),
            ("🔥", "Eigin", 12, false),
            ("🧪", "The Lab", 3, true),
        ]
        for sample in samples {
            let space = Space(agentID: agent.id)
            space.emoji = sample.emoji
            space.name = sample.name
            space.isPrivate = sample.isPrivate
            space.bootstrapComplete = true
            context.insert(space)
            for _ in 0 ..< sample.chats {
                let chat = Chat(agentID: agent.id)
                chat.spaceID = space.id
                context.insert(chat)
            }
        }

        return container
    }())
    .resolveTheme()
    .environment(\.themeManager, ThemeManager())
}

#Preview("Empty") {
    NavigationStack {
        SpaceListView()
    }
    .modelContainer({ () -> ModelContainer in
        let container = try! ModelContainer(
            for: Schema(SchemaV10.models, version: SchemaV10.versionIdentifier),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let provider = Provider(name: "Preview Provider", baseURL: "https://fake.local")
        container.mainContext.insert(provider)
        let agent = Agent(name: "Eigin", providerID: provider.id, model: "gpt-4o")
        agent.bootstrapComplete = true
        container.mainContext.insert(agent)
        return container
    }())
    .resolveTheme()
    .environment(\.themeManager, ThemeManager())
}
