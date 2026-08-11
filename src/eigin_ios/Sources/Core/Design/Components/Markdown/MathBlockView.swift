import SwiftUI

/// Renders a display-math (`$$…$$`) block. The block already holds pure LaTeX,
/// so it goes straight to the math view without a markdown round-trip. Scrolls
/// horizontally so wide equations aren't clipped.
struct MathBlockView: View {
    let latex: String

    @Environment(\.markdownRenderConfig) private var config

    var body: some View {
        // Only scrolls when the equation is actually wider than its container.
        ViewThatFits(in: .horizontal) {
            equation
            ScrollView(.horizontal) {
                equation
            }
            .scrollIndicators(.hidden)
        }
    }

    private var equation: some View {
        HStack(spacing: 0) {
            BlockMathView(latex: latex, color: config.paragraphStyle.textColor)
            Spacer()
        }
    }
}
