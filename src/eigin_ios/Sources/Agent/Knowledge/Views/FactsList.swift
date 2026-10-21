import Factory
import SwiftUI

struct FactsList: View {
    @Environment(\.colors) private var colors
    @Injected(\.knowledgeService) private var knowledgeService

    let agentID: UUID?

    @State private var factsByType: [(type: String, header: String, facts: [FirmEntity])] = []
    @State private var isLoading = true
    @State private var factToDelete: (type: String, id: String)?
    @State private var showDeleteConfirmation = false

    private static let previewLimit = 10
    private static let typeOrder = ["actor", "thing", "fact", "output", "note"]

    private static let typeHeaders: [String: String] = [
        "actor": Localized.Facts.Kind.actors,
        "thing": Localized.Facts.Kind.things,
        "fact": Localized.Facts.Kind.facts,
        "output": Localized.Facts.Kind.outputs,
        "note": Localized.Facts.Kind.notes,
    ]

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if factsByType.isEmpty {
                ContentUnavailableView(
                    Localized.Knowledge.EmptyState.title,
                    systemImage: "book.closed",
                    description: Text(Localized.Knowledge.EmptyState.hint)
                )
            } else {
                List {
                    ForEach(factsByType, id: \.type) { section in
                        Section(section.header) {
                            let preview = Array(section.facts.prefix(Self.previewLimit))
                            ForEach(preview, id: \.id) { entity in
                                factLink(entity)
                            }
                            if section.facts.count > Self.previewLimit {
                                NavigationLink {
                                    FactTypeList(
                                        type: section.type,
                                        header: section.header,
                                        facts: section.facts,
                                        agentID: agentID
                                    )
                                    .hidesTabBar()
                                } label: {
                                    Text(Localized.Ui.showAll("\(section.facts.count)"))
                                        .typography(Typography.note)
                                        .foregroundStyle(colors.accent)
                                }
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .softEdge()
            }
        }
        .background(colors.surface.standard.base.ignoresSafeArea())
        .task { await loadFacts() }
        .refreshable { await loadFacts() }
        .alert(Localized.Common.Actions.delete, isPresented: $showDeleteConfirmation) {
            Button(Localized.Common.Actions.cancel, role: .cancel) {}
            Button(Localized.Common.Actions.delete, role: .destructive) {
                Haptics.error()
                if let fact = factToDelete {
                    Task {
                        try? await knowledgeService.deleteEntity(
                            type: fact.type,
                            id: fact.id,
                            spaceID: nil,
                            agentID: agentID
                        )
                        await loadFacts()
                    }
                }
            }
        } message: {
            Text(Localized.Facts.deleteWarning)
        }
    }

    // MARK: - Rows

    private func factLink(_ entity: FirmEntity) -> some View {
        NavigationLink {
            FactDetail(
                entity: entity,
                isBundled: isBundled(entity),
                agentID: agentID
            )
            .hidesTabBar()
        } label: {
            factRow(entity)
        }
        .swipeActions(edge: .trailing) {
            if !isBundled(entity) {
                Button {
                    let shortID = extractShortID(from: entity.id, type: entity.entityType)
                    factToDelete = (entity.entityType, shortID)
                    showDeleteConfirmation = true
                } label: {
                    Label(Localized.Common.Actions.delete, systemImage: "trash")
                }
                .tint(.red)
            }
        }
    }

    private func factRow(_ entity: FirmEntity) -> some View {
        Text(primaryField(for: entity))
            .typography(Typography.titleXS)
            .foregroundStyle(colors.text.standard.base)
            .lineLimit(2)
    }

    // MARK: - Data Loading

    private func loadFacts() async {
        do {
            let schemas = try await knowledgeService.listSchemas(spaceID: nil, agentID: agentID)
            var sections: [(type: String, header: String, facts: [FirmEntity])] = []

            for type in Self.typeOrder where schemas.contains(type) {
                let ids = try await knowledgeService.listEntities(
                    type: type,
                    spaceID: nil,
                    agentID: agentID
                )
                var entities: [FirmEntity] = []
                for id in ids {
                    if let entity = try await knowledgeService.getEntity(
                        type: type,
                        id: id,
                        spaceID: nil,
                        agentID: agentID
                    ) {
                        entities.append(entity)
                    }
                }

                // Sort by created_at descending, entities without dates last.
                entities.sort { a, b in
                    let dateA = FactsListHelpers.createdAt(for: a)
                    let dateB = FactsListHelpers.createdAt(for: b)
                    switch (dateA, dateB) {
                    case (.some(let da), .some(let db)): return da > db
                    case (.some, .none): return true
                    case (.none, .some): return false
                    case (.none, .none): return a.id < b.id
                    }
                }

                if !entities.isEmpty {
                    let header = Self.typeHeaders[type] ?? type.capitalized
                    sections.append((type: type, header: header, facts: entities))
                }
            }

            factsByType = sections
        } catch {
            factsByType = []
        }
        isLoading = false
    }

    // MARK: - Helpers

    private func primaryField(for entity: FirmEntity) -> String {
        FactsListHelpers.primaryField(for: entity)
    }

    private func isBundled(_ entity: FirmEntity) -> Bool {
        FactsListHelpers.isBundled(entity)
    }

    private func extractShortID(from qualifiedID: String, type: String) -> String {
        FactsListHelpers.extractShortID(from: qualifiedID, type: type)
    }
}

// MARK: - Full Type List

/// Shows all facts for a single type, used when a section has more than the preview limit.
private struct FactTypeList: View {
    @Environment(\.colors) private var colors
    @Injected(\.knowledgeService) private var knowledgeService

    let type: String
    let header: String
    let facts: [FirmEntity]
    let agentID: UUID?

    @State private var factToDelete: (type: String, id: String)?
    @State private var showDeleteConfirmation = false

    var body: some View {
        List {
            ForEach(facts, id: \.id) { entity in
                NavigationLink {
                    FactDetail(
                        entity: entity,
                        isBundled: isBundled(entity),
                        agentID: agentID
                    )
                } label: {
                    Text(primaryField(for: entity))
                        .typography(Typography.titleXS)
                        .foregroundStyle(colors.text.standard.base)
                        .lineLimit(2)
                }
                .swipeActions(edge: .trailing) {
                    if !isBundled(entity) {
                        Button {
                            let shortID = extractShortID(from: entity.id, type: entity.entityType)
                            factToDelete = (entity.entityType, shortID)
                            showDeleteConfirmation = true
                        } label: {
                            Label(Localized.Common.Actions.delete, systemImage: "trash")
                        }
                        .tint(.red)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .softEdge()
        .background(colors.surface.standard.base.ignoresSafeArea())
        .navigationTitle(header, style: Typography.titleXl)
        .navigationBarTitleDisplayMode(.inline)
        .alert(Localized.Common.Alert.deleteFactTitle, isPresented: $showDeleteConfirmation) {
            Button(Localized.Common.Actions.cancel, role: .cancel) {}
            Button(Localized.Common.Actions.delete, role: .destructive) {
                Haptics.error()
                if let fact = factToDelete {
                    Task {
                        try? await knowledgeService.deleteEntity(
                            type: fact.type,
                            id: fact.id,
                            spaceID: nil,
                            agentID: agentID
                        )
                    }
                }
            }
        } message: {
            Text(Localized.Facts.deleteWarning)
        }
    }

    private func primaryField(for entity: FirmEntity) -> String {
        FactsListHelpers.primaryField(for: entity)
    }

    private func isBundled(_ entity: FirmEntity) -> Bool {
        FactsListHelpers.isBundled(entity)
    }

    private func extractShortID(from qualifiedID: String, type: String) -> String {
        FactsListHelpers.extractShortID(from: qualifiedID, type: type)
    }
}

// MARK: - Shared Helpers

// FactsListHelpers is defined in KnowledgeGraph.swift (shared between list and graph views).

#Preview {
    NavigationStack {
        FactsList(agentID: nil)
    }
    .previewEnvironment()
}
