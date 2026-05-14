import Factory
import SwiftUI

/// Wrapper view that toggles between the flat knowledge list and the graph visualization.
///
/// User preference for list vs. graph mode is persisted via `@AppStorage`.
struct KnowledgeContainer: View {
    @Environment(\.colors) private var colors
    @Injected(\.knowledgeService) private var knowledgeService

    let agentID: UUID?

    @AppStorage("knowledgeViewMode") private var viewMode: KnowledgeViewMode = .list
    @State private var graphViewModel: KnowledgeGraphViewModel?

    var body: some View {
        Group {
            switch viewMode {
            case .list:
                FactsList(agentID: agentID)
            case .graph:
                if let vm = graphViewModel {
                    KnowledgeGraph(viewModel: vm, agentID: agentID)
                        .navigationTitle("Knowledge", style: Typography.titleXl)
                        .navigationBarTitleDisplayMode(.inline)
                } else {
                    ProgressView()
                        .task { await loadGraph() }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation(Animations.snap) {
                        viewMode = viewMode == .list ? .graph : .list
                    }
                    if viewMode == .graph, graphViewModel == nil {
                        Task { await loadGraph() }
                    }
                } label: {
                    Image(systemName: viewMode == .list ? "point.3.connected.trianglepath.dotted" :
                        "list.bullet")
                        .foregroundStyle(colors.accent)
                }
            }
        }
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
