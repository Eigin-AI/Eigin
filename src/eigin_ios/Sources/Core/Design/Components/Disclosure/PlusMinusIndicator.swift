import SwiftUI

/// A plus that swaps to a minus when expanded, signalling "reveal more here"
/// rather than the navigational meaning a chevron carries. `AppDisclosure`
/// animates the swap as one symbol replacing the other.
struct PlusMinusIndicator: View {
    let isExpanded: Bool

    @Environment(\.colors) private var colors

    /// Glyph point size, kept compact so it reads as a trailing accent.
    private let size: CGFloat = 16

    var body: some View {
        Image(systemName: isExpanded ? "minus" : "plus")
            .foregroundStyle(colors.icon.standard.muted)
            .contentTransition(.opacity)
            .animation(Animations.snap, value: isExpanded)
            .accessibilityHidden(true)
    }
}

// MARK: - Preview

private struct PlusMinusIndicatorPreview: View {
    @State private var isExpanded = false
    @Environment(\.colors) private var colors

    var body: some View {
        ZStack {
            colors.surface.standard.base.ignoresSafeArea()
            PlusMinusIndicator(isExpanded: isExpanded)
                .onTapGesture { isExpanded.toggle() }
        }
    }
}

#Preview("Light") {
    PlusMinusIndicatorPreview()
        .resolveTheme()
}

#Preview("Dark") {
    PlusMinusIndicatorPreview()
        .resolveTheme()
        .environment(\.colorScheme, .dark)
}
