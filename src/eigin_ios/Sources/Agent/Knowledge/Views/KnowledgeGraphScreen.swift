import Factory
import SwiftUI

/// The bounded knowledge explorer: the user at the center, their immediate
/// connections in fixed slots, a page at a time. No pan, zoom or search — the
/// graph is navigated by recentring, and the previous center is always pinned
/// to the first page as the route back.
struct KnowledgeGraphScreen: View {
    @Environment(\.colors) private var colors
    @Injected(\.knowledgeService) private var knowledgeService

    let agentID: UUID?

    @State private var explorer: KnowledgeExplorer?
    @State private var canvasSize: CGSize = .zero
    @State private var showSummary = false
    @State private var showDetail = false

    var body: some View {
        content
            .background(colors.surface.standard.base.ignoresSafeArea())
            .task {
                guard explorer?.neighborhood == nil else { return }
                do {
                    // Keep this loading view mounted through the entry animation and query.
                    try await Task.sleep(for: .seconds(Animations.slow))
                    try Task.checkCancellation()
                } catch { return }
                if explorer == nil {
                    explorer = KnowledgeExplorer(service: knowledgeService, agentID: agentID)
                }
                if explorer?.neighborhood == nil { await explorer?.load() }
            }
            .onDisappear {
                explorer?.cancel()
            }
            .navigationDestination(isPresented: $showDetail) {
                if let entity = explorer?.neighborhood?.focus {
                    FactDetail(
                        entity: entity,
                        isBundled: KnowledgePresentation.isBundled(entity),
                        agentID: agentID,
                        onDelete: { _ in
                            showDetail = false
                            Task { await explorer?.refresh() }
                        }
                    )
                    .hidesTabBar()
                }
            }
            .appSheet(
                isPresented: $showSummary,
                title: summaryPresentation?.name ?? "",
                description: summaryPresentation?.summary,
                descriptionLineLimit: 4,
                primary: {
                    if summary != nil { summarySheet }
                }
            )
    }

    @ViewBuilder private var content: some View {
        if explorer == nil || ((explorer?.isLoading ?? false) && explorer!.neighborhood == nil) {
            AppLoadingState(title: Localized.Knowledge.Graph.loading)
        } else if let explorer {
            if let _ = explorer.error, explorer.neighborhood == nil {
                AppEmptyState(
                    icon: Iconography.Functional.warning,
                    title: Localized.Knowledge.Error.title,
                    description: Localized.Knowledge.Error.hint
                ) {
                    AppButton(Localized.Common.Actions.retry, variant: .secondary, size: .medium) {
                        Task { await explorer.retry() }
                    }
                }
            } else if explorer.root == nil {
                AppEmptyState(
                    icon: Iconography.Functional.asterix,
                    title: Localized.Knowledge.EmptyState.title,
                    description: Localized.Knowledge.EmptyState.hint
                )
            } else {
                explorer_(explorer)
            }
        }
    }

    private func explorer_(_ explorer: KnowledgeExplorer) -> some View {
        GeometryReader { geometry in
            let short = geometry.size.height < 300
            VStack(spacing: short ? Spacing.n8 : Spacing.n16) {
                graph(explorer)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                controls(explorer, horizontal: short)
                    .padding(.bottom, short ? Spacing.n8 : Spacing.n16)
            }
            .padding(.horizontal, Spacing.n8)
        }
    }

    // MARK: - Canvas

    private func graph(_ explorer: KnowledgeExplorer) -> some View {
        KnowledgeGraphCanvas(
            placements: placements,
            compact: canvasSize.height < 300,
            onSelect: { entity in Task { await explorer.focus(entity) } },
            onDetails: { showSummary = true }
        )
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            if canvasSize != size {
                canvasSize = size
                explorer.setCapacity(size.height < 300 ? 4 : 6)
            }
        }
    }

    private var placements: [KnowledgeGraphPlacement] {
        guard let explorer, let focus = explorer.neighborhood?.focus,
              canvasSize != .zero else { return [] }
        let visible = explorer.visibleNeighbors
        let slots = KnowledgeGraphLayout.slots(count: visible.count, size: canvasSize)
        return [KnowledgeGraphPlacement(
            entity: focus,
            position: KnowledgeGraphLayout.position(x: 50, y: 50, size: canvasSize),
            isFocus: true
        )] + visible.enumerated().map { index, entity in
            KnowledgeGraphPlacement(
                entity: entity,
                position: slots[index],
                isFocus: false
            )
        }
    }

    // MARK: - Controls

    private func controls(_ explorer: KnowledgeExplorer, horizontal: Bool) -> some View {
        let layout = horizontal ? AnyLayout(HStackLayout(spacing: Spacing.n8)) :
            AnyLayout(VStackLayout(spacing: 0))
        return layout {
            pagination(explorer)
            HStack(spacing: Spacing.n16) {
                if explorer.arrivedFrom != nil || explorer.page != 0 {
                    AppButton(
                        Localized.Knowledge.Graph.backToYou,
                        variant: .open,
                        size: .extraSmall
                    ) {
                        Task { await explorer.reset() }
                    }
                }
            }
            .frame(height: Sizing.Button.Action.extraSmall, alignment: .center)
            .frame(minWidth: 168)
        }
    }

    private func pagination(_ explorer: KnowledgeExplorer) -> some View {
        let pages = explorer.pageCount
        return HStack(spacing: Spacing.n8) {
            if explorer.error != nil {
                Text(Localized.Knowledge.Error.hint)
                    .typography(Typography.note)
                    .foregroundStyle(colors.text.standard.muted)
                    .lineLimit(2)
                AppButton(Localized.Common.Actions.retry, variant: .open, size: .extraSmall) {
                    Task { await explorer.retry() }
                }
                .disabled(explorer.isLoading)
            } else {
                if pages > 1 {
                    AppActionButton(
                        icon: Iconography.Functional.Chevron.left,
                        variant: .open,
                        size: .small
                    ) {
                        explorer.setPage(explorer.page - 1)
                    }
                    .disabled(explorer.page == 0)
                    .accessibilityLabel(Localized.Knowledge.Graph.previous)
                }
                Text(countText(count: explorer.neighbors.count, pages: pages, explorer: explorer))
                    .typography(Typography.note)
                    .foregroundStyle(colors.text.standard.muted)
                if pages > 1 {
                    AppActionButton(
                        icon: Iconography.Functional.Chevron.right,
                        variant: .open,
                        size: .small
                    ) {
                        explorer.setPage(explorer.page + 1)
                    }
                    .disabled(explorer.page + 1 >= pages)
                    .accessibilityLabel(Localized.Knowledge.Graph.next)
                }
            }
        }
        .frame(height: Sizing.Button.Action.small, alignment: .center)
    }

    private func countText(count: Int, pages: Int, explorer: KnowledgeExplorer) -> String {
        if count == 0 {
            return Localized.Knowledge.Graph.noConnections
        }
        if pages > 1 {
            return Localized.Knowledge.Graph.connectionRange(
                "\(explorer.page * explorer.capacity + 1)",
                "\(min((explorer.page + 1) * explorer.capacity, count))",
                "\(count)"
            )
        }
        let word = count == 1
            ? Localized.Knowledge.Graph.connection
            : Localized.Knowledge.Graph.connections
        return "\(count) \(word)"
    }

    // MARK: - Summary sheet

    private var summary: FirmEntity? {
        explorer?.neighborhood?.focus
    }

    private var summaryPresentation: KnowledgePresentation? {
        summary.map(KnowledgePresentation.init)
    }

    private var summarySheet: some View {
        let related = explorer?.neighbors ?? []
        return VStack(spacing: Sizing.PageLayout.gap) {
            AppContentGroup {
                AppRow(
                    AppRowSpec(
                        title: Localized.Knowledge.Sheet.viewFullDetails,
                        action: {
                            showSummary = false
                            showDetail = true
                        }
                    )
                )
            }
            AppContentGroup(label: Localized.Knowledge.Graph.connectionsSection) {
                if related.isEmpty {
                    AppRow(
                        AppRowSpec(
                            title: Localized.Knowledge.Graph.noConnections,
                            accessory: .none
                        )
                    )
                } else {
                    ForEach(Array(related.enumerated()), id: \.element.id) { index, entity in
                        if index > 0 { RowHairline() }
                        relationshipRow(entity)
                    }
                }
            }
        }
        .padding(.horizontal, Spacing.n16)
    }

    private func relationshipRow(_ entity: FirmEntity) -> some View {
        AppRow(
            AppRowSpec(
                title: KnowledgePresentation(entity).name,
                action: {
                    showSummary = false
                    Task { await explorer?.focus(entity) }
                }
            )
        )
    }
}

// MARK: - Type icons

/// Canonical type-to-icon mapping, mirroring the design system.
enum KnowledgeIcons {
    static func icon(for entity: FirmEntity) -> Image {
        switch entity.entityType {
        case "actor": Iconography.Functional.avatar
        case "thing": Iconography.Functional.box
        case "fact": Iconography.Functional.asterix
        case "output": Iconography.Functional.document
        case "note": Iconography.Functional.listCheck
        default: Iconography.Functional.circle
        }
    }
}

#Preview {
    NavigationStack {
        KnowledgeGraphScreen(agentID: nil)
    }
    .previewEnvironment()
}
