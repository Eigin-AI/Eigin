import Factory
import SwiftUI

/// Wrapper view that toggles between the flat knowledge list and the graph visualization.
///
/// User preference for list vs. graph mode is persisted via `@AppStorage`.
struct KnowledgeContainer: View {
    @Environment(\.colors) private var colors
    @Environment(\.dismiss) private var dismiss
    @Injected(\.knowledgeService) private var knowledgeService

    let agentID: UUID?

    @AppStorage("knowledgeViewMode") private var viewMode: KnowledgeViewMode = .list
    @State private var graphViewModel: KnowledgeGraphViewModel?

    var body: some View {
        VStack(spacing: 0) {
            AppNavigationHeader(
                title: Localized.Knowledge.sectionTitle,
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
                        icon: Image(systemName: viewMode == .list
                            ? "point.3.connected.trianglepath.dotted"
                            : "list.bullet"),
                        variant: .open,
                        size: .medium,
                        action: {
                            withAnimation(Animations.snap) {
                                viewMode = viewMode == .list ? .graph : .list
                            }
                            if viewMode == .graph, graphViewModel == nil {
                                Task { await loadGraph() }
                            }
                        }
                    )
                }
            )

            switch viewMode {
            case .list:
                FactsList(agentID: agentID)
            case .graph:
                if let vm = graphViewModel {
                    KnowledgeGraph(viewModel: vm, agentID: agentID)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .task { await loadGraph() }
                }
            }
        }
        .background(colors.surface.standard.base.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    private func loadGraph() async {
        let vm = KnowledgeGraphViewModel(knowledgeService: knowledgeService, agentID: agentID)
        graphViewModel = vm
        await vm.loadInitialGraph()
    }
}

// MARK: - View Mode

enum KnowledgeViewMode: String {
    case list
    case graph
}

#Preview {
    NavigationStack {
        KnowledgeContainer(agentID: nil)
    }
    .previewEnvironment()
}
