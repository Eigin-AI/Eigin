import SwiftUI

/// Fixed graph rendering with animation state isolated from screen controls and sheets.
struct KnowledgeGraphCanvas: View {
    let placements: [KnowledgeGraphPlacement]
    let compact: Bool
    let onSelect: (FirmEntity) -> Void
    let onDetails: () -> Void

    @Environment(\.colors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var transition = KnowledgeGraphTransition()

    var body: some View {
        ZStack {
            lines
            ForEach(transition.shown) { placement in
                KnowledgeGraphNode(
                    placement: placement,
                    compact: compact,
                    isVisible: transition.visible.contains(placement.id),
                    labelsMounted: transition.labelsMounted || transition.preservedLabels
                        .contains(placement.id),
                    labelVisible: transition.revealed.contains(placement.id)
                ) {
                    guard !transition.isTransitioning else { return }
                    if placement.isFocus {
                        onDetails()
                    } else {
                        onSelect(placement.entity)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: Update(placements: placements, reducedMotion: reduceMotion)) {
            await transition.update(placements, reducedMotion: reduceMotion)
        }
        .onDisappear { transition.cancel() }
    }

    private struct Update: Equatable {
        let placements: [KnowledgeGraphPlacement]
        let reducedMotion: Bool
    }

    private var lines: some View {
        ZStack {
            if let focus = transition.shown.first(where: \.isFocus) {
                ForEach(transition.shown.filter { !$0.isFocus }) { node in
                    let ready = transition.linesVisible && transition.revealed.contains(focus.id)
                        && transition.revealed.contains(node.id)
                    Path { path in
                        path.move(to: circleCenter(focus.position))
                        path.addLine(to: circleCenter(node.position))
                    }
                    .stroke(colors.border.standard.base, lineWidth: 1.5)
                    .opacity(ready ? 0.8 : 0)
                    .animation(
                        reduceMotion ? nil : .linear(duration: ready ? 0.12 : 0.08),
                        value: ready
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }

    /// Circle centers sit 20pt above the whole circle-and-label node's layout point.
    private func circleCenter(_ position: CGPoint) -> CGPoint {
        CGPoint(x: position.x, y: position.y - 20)
    }
}

private struct KnowledgeGraphNode: View {
    let placement: KnowledgeGraphPlacement
    let compact: Bool
    let isVisible: Bool
    let labelsMounted: Bool
    let labelVisible: Bool
    let action: () -> Void

    @Environment(\.colors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let name = placement.name
        VStack(spacing: Spacing.n8) {
            circle
            ZStack(alignment: .top) {
                if labelsMounted {
                    Text(name)
                        .typography(Typography.tag)
                        .foregroundStyle(
                            placement.isFocus ? colors.text.standard.base : colors.text.standard
                                .muted
                        )
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .frame(width: Spacing.n80)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(width: Spacing.n80, height: Spacing.n40, alignment: .top)
            .opacity(labelVisible ? 1 : 0)
            .animation(
                reduceMotion ? nil : .linear(duration: labelVisible ? 0.12 : 0.08),
                value: labelVisible
            )
        }
        .padding(.top, compact || placement.isFocus ? 0 : Spacing.n12)
        .frame(width: Spacing.n88, height: nodeHeight, alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .accessibilityLabel(
            placement.isFocus
                ? Localized.Knowledge.Graph.details(name)
                : Localized.Knowledge.Graph.explore(name)
        )
        .accessibilityAddTraits(.isButton)
        .scaleEffect(isVisible ? 1 : 0.001)
        .position(placement.position)
    }

    private var circle: some View {
        KnowledgeIcons.icon(for: placement.entity)
            .resizable()
            .scaledToFit()
            .frame(
                width: placement.isFocus ? Spacing.n32 : Spacing.n24,
                height: placement.isFocus ? Spacing.n32 : Spacing.n24
            )
            .foregroundStyle(
                placement.isFocus ? colors.icon.impact.base : colors.icon.standard.base
            )
            .frame(width: diameter, height: diameter)
            .background {
                Circle().fill(
                    placement.isFocus ? colors.button.spot.base : colors.surface.standard
                        .alternative
                )
            }
    }

    private var diameter: CGFloat {
        compact ? (placement.isFocus ? Spacing.n56 : Spacing.n40)
            : (placement.isFocus ? Spacing.n72 : Spacing.n48)
    }

    private var nodeHeight: CGFloat {
        compact ? (placement.isFocus ? 96 : Spacing.n80) : 112
    }
}
