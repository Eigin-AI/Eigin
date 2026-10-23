import Factory
import SwiftUI

/// Four-item category previews with access to the complete knowledge lists.
struct FactsList: View {
    @Environment(\.colors) private var colors
    @Injected(\.knowledgeService) private var knowledgeService
    let agentID: UUID?
    @State private var library: KnowledgeLibrary?

    var body: some View {
        Group {
            if library == nil || (library!.isLoading && library!.categories.isEmpty) {
                AppLoadingState(title: Localized.Knowledge.Graph.loadingList)
            } else if let library, library.error != nil, library.categories.isEmpty {
                AppEmptyState(
                    icon: Iconography.Functional.warning,
                    title: Localized.Knowledge.Error.title,
                    description: Localized.Knowledge.Error.hint
                ) {
                    AppButton(Localized.Common.Actions.retry, variant: .secondary, size: .medium) {
                        Task { await library.load() }
                    }
                }
            } else if let library, !library.categories.isEmpty {
                SoftEdgeScrollView {
                    VStack(spacing: Sizing.PageLayout.gap) {
                        if library.error != nil { KnowledgeLibraryRetry(library: library) }
                        ForEach(library.categories) { category in
                            AppContentGroup(label: KnowledgeLabels.categoryName(category.type)) {
                                KnowledgeRows(
                                    items: category.preview,
                                    agentID: agentID,
                                    onDelete: library.remove
                                )
                                if category.hasMore {
                                    RowHairline()
                                    NavigationLink {
                                        KnowledgeCategoryScreen(
                                            type: category.type,
                                            library: library,
                                            agentID: agentID
                                        )
                                        .hidesTabBar()
                                    } label: {
                                        AppRow(AppRowSpec(
                                            title: Localized.Knowledge
                                                .showAll(KnowledgeLabels.categoryName(category.type)
                                                    .lowercased()),
                                            value: "\(category.items.count)", tone: .muted
                                        ))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, Spacing.n16)
                    .padding(.top, Spacing.n8)
                    .padding(.bottom, Spacing.n32)
                }
                .refreshable { await library.load() }
            } else {
                AppEmptyState(
                    icon: Iconography.Functional.asterix,
                    title: Localized.Knowledge.EmptyState.title,
                    description: Localized.Knowledge.EmptyState.hint
                )
            }
        }
        .background(colors.surface.standard.base.ignoresSafeArea())
        .task {
            if library == nil {
                do {
                    // One loading ring remains mounted through the entry delay and query.
                    try await Task.sleep(for: .seconds(Animations.slow))
                    try Task.checkCancellation()
                } catch { return }
                library = KnowledgeLibrary(service: knowledgeService, agentID: agentID)
            }
            await library?.load()
        }
    }
}

/// Shared knowledge rows use stored names and a two-line content preview.
struct KnowledgeRows: View {
    let items: [KnowledgeItem]
    let agentID: UUID?
    let onDelete: (String) -> Void

    var body: some View {
        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
            if index > 0 { RowHairline() }
            NavigationLink {
                FactDetail(
                    entity: item.entity,
                    isBundled: KnowledgePresentation.isBundled(item.entity),
                    agentID: agentID,
                    onDelete: onDelete
                )
                .hidesTabBar()
            } label: {
                AppRow(AppRowSpec(
                    id: item.id,
                    title: item.presentation.name,
                    description: item.presentation.content,
                    descriptionLineLimit: 2
                ))
                .multilineTextAlignment(.leading)
            }
            .buttonStyle(.plain)
        }
    }
}

#Preview {
    NavigationStack { FactsList(agentID: nil) }.previewEnvironment()
}

/// Retained category rows remain usable when a refresh fails.
struct KnowledgeLibraryRetry: View {
    let library: KnowledgeLibrary

    var body: some View {
        AppRowsGroup(rows: [AppRowSpec(
            title: Localized.Common.Actions.retry,
            description: Localized.Knowledge.Error.hint,
            action: { Task { await library.load() } }
        )])
    }
}
