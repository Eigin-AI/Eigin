import SwiftUI

/// The complete category, sharing the library so deletion updates its preview too.
struct KnowledgeCategoryScreen: View {
    let type: String
    let library: KnowledgeLibrary
    let agentID: UUID?
    @State private var visibleCount = 20

    private var items: [KnowledgeItem] {
        library.categories.first(where: { $0.type == type })?.items ?? []
    }

    var body: some View {
        AppSecondaryScreen(
            title: KnowledgeLabels.categoryName(type),
            fillsViewport: items.isEmpty
        ) {
            if library.error != nil { KnowledgeLibraryRetry(library: library) }
            if items.isEmpty, library.error == nil {
                AppEmptyState(
                    icon: Iconography.Functional.asterix,
                    title: Localized.Knowledge.EmptyState.title,
                    description: Localized.Knowledge.EmptyState.hint
                )
            } else if !items.isEmpty {
                AppContentGroup {
                    LazyVStack(spacing: 0) {
                        KnowledgeRows(
                            items: Array(items.prefix(visibleCount)),
                            agentID: agentID,
                            onDelete: library.remove
                        )
                        if visibleCount < items.count {
                            RowHairline()
                            AppRow(AppRowSpec(
                                title: Localized.Knowledge
                                    .showMore("\(min(20, items.count - visibleCount))"),
                                tone: .muted,
                                action: { visibleCount += 20 }
                            ))
                        }
                    }
                }
            }
        }
        .refreshable { await library.load() }
    }
}
