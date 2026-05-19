import SwiftData
import SwiftUI

struct SpaceListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colors) private var colors
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

    @State private var spaceToDelete: Space?
    @State private var showDeleteConfirmation = false
    @State private var showBootstrap = false

    var body: some View {
        Group {
            if spaces.isEmpty {
                ContentUnavailableView(
                    Localized.Space.title,
                    systemImage: "square.grid.2x2",
                    description: Text(Localized.Space.EmptyState.hint)
                )
            } else {
                List {
                    ForEach(Array(spaces.enumerated()), id: \.element.id) { index, space in
                        NavigationLink {
                            SpaceDetailView(space: space)
                                .hidesTabBar()
                        } label: {
                            spaceRow(for: space)
                        }
                        .listRowSeparator(.visible, edges: .bottom)
                        .listRowSeparator(index == 0 ? .hidden : .visible, edges: .top)
                        .listRowBackground(Color.clear)
                        .swipeActions(edge: .trailing) {
                            Button {
                                spaceToDelete = space
                                showDeleteConfirmation = true
                            } label: {
                                Label(Localized.Common.Actions.delete, systemImage: "trash")
                            }
                            .tint(.red)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(colors.surface.standard.base.ignoresSafeArea())
        .navigationTitle(Localized.Space.title, style: Typography.titleXl)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showBootstrap = true
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(agent == nil || activeProvider == nil)
            }
        }
        .navigationDestination(isPresented: $showBootstrap) {
            if let agent, let provider = activeProvider {
                SpaceBootstrapView(agent: agent, provider: provider)
                    .hidesTabBar()
            }
        }
        .alert(Localized.Common.Alert.deleteSpaceTitle, isPresented: $showDeleteConfirmation) {
            Button(Localized.Common.Actions.cancel, role: .cancel) {}
            Button(Localized.Common.Actions.delete, role: .destructive) {
                Haptics.error()
                if let space = spaceToDelete {
                    deleteSpace(space)
                }
            }
        } message: {
            Text(Localized.Space.deleteWarning)
        }
    }

    private func spaceRow(for space: Space) -> some View {
        HStack(spacing: Spacing.n8) {
            Text(space.emoji)
                .font(.system(size: 24))
            VStack(alignment: .leading, spacing: 2) {
                Text(space.name.isEmpty ? Localized.Space.List.untitledSpace : space.name)
                    .typography(Typography.titleXS)
                    .foregroundStyle(colors.text.standard.base)
                let count = chatCount(for: space)
                Text(Localized.Space.List.chatsCount("\(count)"))
                    .typography(Typography.miniLabel)
                    .foregroundStyle(colors.text.standard.muted)
            }
            Spacer()
            if space.isPrivate {
                Image(systemName: "eye.slash")
                    .typography(Typography.miniLabel)
                    .foregroundStyle(colors.text.standard.muted)
            }
        }
    }

    private func chatCount(for space: Space) -> Int {
        allChats.count(where: { $0.spaceID == space.id })
    }

    private func deleteSpace(_ space: Space) {
        let spaceID = space.id
        for chat in allChats where chat.spaceID == spaceID {
            chat.spaceID = nil
        }
        if let context = agent?.modelContext {
            let agentID = agent!.id
            let descriptor = FetchDescriptor<FirmSource>(
                predicate: #Predicate { $0.agentID == agentID && $0.spaceID == spaceID }
            )
            if let sources = try? context.fetch(descriptor) {
                for source in sources {
                    source.spaceID = nil
                }
            }
        }
        modelContext.delete(space)
    }
}
