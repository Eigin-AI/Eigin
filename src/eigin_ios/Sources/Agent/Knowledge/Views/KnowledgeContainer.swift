import SwiftUI

/// Knowledge entry: the graph explorer by default, with a segmented control
/// switching to the flat list. The mode follows the visit — it does not persist.
struct KnowledgeContainer: View {
    @Environment(\.colors) private var colors
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let agentID: UUID?

    @State private var viewMode: Mode = .graph

    enum Mode { case graph, list }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                switch viewMode {
                case .graph:
                    KnowledgeGraphScreen(agentID: agentID)
                case .list:
                    FactsList(agentID: agentID)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    if geometry.size.height < 450 {
                        ZStack {
                            Text(Localized.Knowledge.sectionTitle)
                                .typography(Typography.titleXS)
                                .foregroundStyle(colors.text.standard.base)
                            HStack {
                                AppActionButton(
                                    icon: Iconography.Functional.Arrow.left,
                                    variant: .open,
                                    size: .medium,
                                    action: { dismiss() }
                                )
                                .accessibilityLabel(Localized.Common.Actions.back)
                                Spacer()
                            }
                        }
                        .frame(height: Sizing.Button.Action.medium)
                        .padding(.horizontal, Spacing.n16)
                    } else {
                        AppNavigationHeader(
                            title: Localized.Knowledge.sectionTitle,
                            leading: {
                                AppActionButton(
                                    icon: Iconography.Functional.Arrow.left,
                                    variant: .open,
                                    size: .medium,
                                    action: { dismiss() }
                                )
                                .accessibilityLabel(Localized.Common.Actions.back)
                            }
                        )
                    }
                    AppSegmentedControl(
                        segments: [
                            AppSegment(Localized.Knowledge.Graph.modeGraph, value: Mode.graph),
                            AppSegment(Localized.Knowledge.Graph.modeList, value: Mode.list),
                        ],
                        selection: viewMode
                    ) { mode in
                        withAnimation(reduceMotion ? nil : Animations.snap) { viewMode = mode }
                    }
                    .padding(.horizontal, Spacing.n16)
                    .padding(.bottom, Spacing.n8)
                }
                .background(colors.surface.standard.base)
            }
        }
        .background(colors.surface.standard.base.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }
}

#Preview {
    NavigationStack {
        KnowledgeContainer(agentID: nil)
    }
    .previewEnvironment()
}
