import SwiftData
import SwiftUI

struct SpaceListView: View {
    @Environment(\.colors) private var colors
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Space.name) private var spaces: [Space]
    @Query(filter: #Predicate<Agent> { $0.bootstrapComplete })
    private var agents: [Agent]
    @Query(sort: \Chat.updatedAt) private var allChats: [Chat]

    private var agent: Agent? {
        agents.first
    }

    private var activeProvider: Provider? {
        guard let agent else { return nil }
        return providers.first { $0.id == agent.providerID }
    }

    @Query(sort: \Provider.createdAt) private var providers: [Provider]

    @State private var selectedSpace: Space?
    @State private var showBootstrap = false

    var body: some View {
        VStack(spacing: 0) {
            AppNavigationHeader(
                title: Localized.Space.title,
                leading: {
                    AppActionButton(
                        icon: Iconography.Functional.Arrow.left,
                        variant: .open,
                        size: .medium,
                        action: { dismiss() }
                    )
                },
                trailing: {
                    AppActionButton(
                        icon: Iconography.Functional.plus,
                        variant: .open,
                        size: .medium,
                        action: { showBootstrap = true }
                    )
                    .disabled(agent == nil || activeProvider == nil)
                }
            )

            if spaces.isEmpty {
                ContentUnavailableView(
                    Localized.Space.title,
                    systemImage: "square.grid.2x2",
                    description: Text(Localized.Space.EmptyState.hint)
                )
            } else {
                spaceList
            }
        }
        .background(colors.surface.standard.base.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $selectedSpace) { space in
            SpaceDetailView(space: space)
                .hidesTabBar()
        }
        .navigationDestination(isPresented: $showBootstrap) {
            if let agent, let provider = activeProvider {
                SpaceBootstrapView(agent: agent, provider: provider)
                    .hidesTabBar()
            }
        }
    }

    private var spaceList: some View {
        ScrollView {
            LazyVStack(spacing: Sizing.PageLayout.ContentGrouping.gap) {
                ForEach(spaces) { space in
                    AppCardSurface(padding: Spacing.n16, action: { selectedSpace = space }) {
                        spaceRow(for: space)
                    }
                }
            }
            .padding(.horizontal, Spacing.n16)
            .padding(.top, Spacing.n8)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func spaceRow(for space: Space) -> some View {
        HStack(spacing: Spacing.n12) {
            Text(space.emoji)
                .font(.system(size: 32))
            VStack(alignment: .leading, spacing: 2) {
                Text(space.name.isEmpty ? Localized.Space.List.untitledSpace : space.name)
                    .typography(Typography.titleXS)
                    .foregroundStyle(colors.text.standard.base)
                    .lineLimit(1)
                let count = chatCount(for: space)
                Text(Localized.Space.List.chatsCount("\(count)"))
                    .typography(Typography.tag)
                    .foregroundStyle(colors.text.standard.muted)
            }
            Spacer()
            if space.isPrivate {
                Image(systemName: "eye.slash")
                    .typography(Typography.miniLabel)
                    .foregroundStyle(colors.text.standard.muted)
            }
            Image(systemName: "chevron.right")
                .typography(Typography.miniLabel)
                .foregroundStyle(colors.text.standard.muted)
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
            for: Schema(SchemaV2.models, version: SchemaV2.versionIdentifier),
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
            for: Schema(SchemaV2.models, version: SchemaV2.versionIdentifier),
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
