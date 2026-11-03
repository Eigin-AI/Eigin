import SwiftUI

/// A horizontal card row sized to its tallest intrinsic card, including offscreen cards.
struct EqualHeightCardRow: Layout {
    var width: CGFloat = 300
    var spacing: CGFloat = Spacing.n12

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let height = subviews.map {
            $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height
        }.max() ?? 0
        return CGSize(
            width: CGFloat(subviews.count) * width + CGFloat(max(0, subviews.count - 1)) * spacing,
            height: height
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        for (index, subview) in subviews.enumerated() {
            subview.place(
                at: CGPoint(x: bounds.minX + CGFloat(index) * (width + spacing), y: bounds.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: width, height: bounds.height)
            )
        }
    }
}
