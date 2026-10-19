import SwiftUI

/// Wraps text as evenly as it can, like CSS `text-wrap: balance`: the text gets
/// the narrowest width that still fits it in as many lines as the full width
/// would, so a last line never trails off with a single word.
///
/// Holds one subview, typically a multiline `Text`, centred in the width offered.
struct BalancedLines: Layout {
    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache _: inout ()
    ) -> CGSize {
        guard let text = subviews.first else { return .zero }
        let size = text.sizeThatFits(ProposedViewSize(
            width: balancedWidth(of: text, within: proposal.width),
            height: nil
        ))
        return CGSize(width: proposal.width ?? size.width, height: size.height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache _: inout ()
    ) {
        guard let text = subviews.first else { return }
        text.place(
            at: CGPoint(x: bounds.midX, y: bounds.minY),
            anchor: .top,
            proposal: ProposedViewSize(
                width: balancedWidth(of: text, within: bounds.width),
                height: nil
            )
        )
    }

    /// Narrows the width to within a point while the text keeps its height.
    private func balancedWidth(of text: LayoutSubview, within available: CGFloat?) -> CGFloat? {
        guard let available, available.isFinite else { return available }
        func height(at width: CGFloat) -> CGFloat {
            text.sizeThatFits(ProposedViewSize(width: width, height: nil)).height
        }
        let lines = height(at: available)
        var low: CGFloat = 0
        var high = available
        while high - low > 1 {
            let mid = (low + high) / 2
            if height(at: mid) > lines + 0.5 { low = mid } else { high = mid }
        }
        return high
    }
}
