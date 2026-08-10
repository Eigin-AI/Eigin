import SwiftUI

/// Lays out table cells in a fixed number of columns, row-major.
///
/// Sizes in two passes, which is what lets a long cell wrap. Inside a horizontal scroll
/// view nothing proposes a bounded width, so a `Text` reports its ideal single-line width
/// and a width cap only clips. The first pass takes each column's widest ideal, clamped to
/// `maxColumnWidth`; the second re-measures row heights at that settled width.
///
/// Columns and rows sit flush against each other; cells carry their own padding, so the
/// rules drawn on cell edges join up into continuous lines.
struct MarkdownTableLayout: Layout {
    let columnCount: Int
    let maxColumnWidth: CGFloat
    /// Width the table stretches to fill when its content is narrower, so its rules reach
    /// the card edges. Zero leaves the table sized to content.
    var minTableWidth: CGFloat = 0

    struct Cache {
        var columnWidths: [CGFloat]
        var rowHeights: [CGFloat]
    }

    func makeCache(subviews: Subviews) -> Cache {
        measure(subviews)
    }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        cache = measure(subviews)
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) -> CGSize {
        CGSize(
            width: max(cache.columnWidths.reduce(0, +), minTableWidth),
            height: cache.rowHeights.reduce(0, +)
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) {
        guard columnCount > 0 else { return }
        let widths = stretched(cache.columnWidths, toFill: bounds.width)
        var y = bounds.minY
        for row in cache.rowHeights.indices {
            var x = bounds.minX
            for column in 0 ..< columnCount {
                let index = row * columnCount + column
                guard index < subviews.count else { break }
                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    proposal: ProposedViewSize(
                        width: widths[column],
                        height: cache.rowHeights[row]
                    )
                )
                x += widths[column]
            }
            y += cache.rowHeights[row]
        }
    }

    /// Scales columns up proportionally to fill any slack width, keeping their relative
    /// sizes. Columns wider than the available width are left alone: the table scrolls.
    private func stretched(_ widths: [CGFloat], toFill available: CGFloat) -> [CGFloat] {
        let content = widths.reduce(0, +)
        guard content > 0, available > content else { return widths }
        let scale = available / content
        return widths.map { $0 * scale }
    }

    private func measure(_ subviews: Subviews) -> Cache {
        guard columnCount > 0 else { return Cache(columnWidths: [], rowHeights: []) }
        let rowCount = subviews.count / columnCount

        var columnWidths = Array(repeating: CGFloat.zero, count: columnCount)
        for row in 0 ..< rowCount {
            for column in 0 ..< columnCount {
                let ideal = subviews[row * columnCount + column].sizeThatFits(.unspecified).width
                columnWidths[column] = min(max(columnWidths[column], ideal), maxColumnWidth)
            }
        }

        var rowHeights = Array(repeating: CGFloat.zero, count: rowCount)
        for row in 0 ..< rowCount {
            var height: CGFloat = 0
            for column in 0 ..< columnCount {
                let measured = subviews[row * columnCount + column].sizeThatFits(
                    ProposedViewSize(width: columnWidths[column], height: nil)
                ).height
                height = max(height, measured.isFinite ? measured : 0)
            }
            rowHeights[row] = height
        }

        return Cache(columnWidths: columnWidths, rowHeights: rowHeights)
    }
}
