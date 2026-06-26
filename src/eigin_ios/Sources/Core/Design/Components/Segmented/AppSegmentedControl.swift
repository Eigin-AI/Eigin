import SwiftUI

/// A pill-shaped selector that holds equally sized segments with a sliding pill
/// marking the choice. The indicator sits flush with the track edges and glides
/// to the tapped segment. Like `AppSwitch`, it follows the codebase's value +
/// action convention: it reflects `selection` and calls `onSelect` on tap,
/// leaving state to the caller.
struct AppSegmentedControl<Value: Hashable>: View {
    let segments: [AppSegment<Value>]
    let selection: Value
    let onSelect: (Value) -> Void

    @Environment(\.colors) private var colors
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        GeometryReader { geometry in
            let trackWidth = geometry.size.width - indicatorPadding * 2
            let segmentWidth = trackWidth / CGFloat(max(segments.count, 1))

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(colors.interaction.active.fill)
                    .frame(width: segmentWidth)
                    .offset(x: segmentWidth * CGFloat(selectedIndex))

                HStack(spacing: 0) {
                    ForEach(segments) { segment in
                        Text(segment.label)
                            .typography(Typography.navTab)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(labelColor(for: segment.value))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                            .onTapGesture { if isEnabled { onSelect(segment.value) } }
                            .accessibilityAddTraits(traits(for: segment.value))
                    }
                }
            }
            .padding(indicatorPadding)
            .animation(Animations.snap, value: selection)
        }
        .frame(height: Sizing.SegmentedControl.Track.height)
        .background(colors.input.standard.inactive, in: Capsule())
        .opacity(isEnabled ? 1 : 0.5)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Layout

    /// Inset between the track edge and the indicator pill, mirroring the gap
    /// `AppSwitch` keeps around its knob.
    private var indicatorPadding: CGFloat {
        Spacing.n4
    }

    /// Index of the selected segment, falling back to the first so the indicator
    /// always has a home if `selection` is not among the segments.
    private var selectedIndex: Int {
        segments.firstIndex { $0.value == selection } ?? 0
    }

    // MARK: - Colors

    private func labelColor(for value: Value) -> Color {
        value == selection ? colors.text.button.onSpot : colors.text.standard.muted
    }

    // MARK: - Accessibility

    private func traits(for value: Value) -> AccessibilityTraits {
        value == selection ? [.isButton, .isSelected] : .isButton
    }
}

// MARK: - Preview

private struct AppSegmentedControlPreview: View {
    private enum Tab: CaseIterable {
        case reactive, balanced, proactive

        var label: String {
            switch self {
            case .reactive: "Reactive"
            case .balanced: "Balanced"
            case .proactive: "Proactive"
            }
        }
    }

    @State private var selection = Tab.reactive

    private var segments: [AppSegment<Tab>] {
        Tab.allCases.map { AppSegment($0.label, value: $0) }
    }

    var body: some View {
        SwitchPreview {
            VStack(alignment: .leading, spacing: Spacing.n24) {
                AppSegmentedControl(segments: segments, selection: selection) {
                    selection = $0
                }
                AppSegmentedControl(segments: segments, selection: .balanced) { _ in }
                    .disabled(true)
            }
        }
    }
}

#Preview("Light") {
    AppSegmentedControlPreview()
        .resolveTheme()
}

#Preview("Dark") {
    AppSegmentedControlPreview()
        .resolveTheme()
        .environment(\.colorScheme, .dark)
}
