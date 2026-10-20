import SwiftUI

/// Renders a markdown table inside a rounded elevated card, matching the code card, with a
/// faint grid inside: a full-strength rule under the header and lighter rules between rows
/// and columns. Body text matches the assistant's prose; the header sits in a smaller label
/// style so it reads as a column heading.
///
/// Wide tables scroll horizontally within the card. Columns are capped so a long cell
/// wraps, and the cap scales with the space available, so a table gets more room on a
/// wider screen.
struct MarkdownTableView: View {
    let table: MarkdownTable

    @Environment(\.colors) private var colors

    /// Measured width of the scroll view, not its content: deriving the cap from the
    /// content would feed the cap back into the thing it determines.
    @State private var availableWidth: CGFloat = 0

    /// Floor for the column cap, used until the width is measured and on narrow screens.
    private static let minimumColumnCap: CGFloat = 240

    /// Opacity of the interior grid rules, kept below the header's so it reads softest.
    private static let faintRule: Double = 0.35

    /// Opacity of the header's rule. Kept above the interior rules so it stays the
    /// strongest line, but held below full strength so the grid reads softly.
    private static let headerRule: Double = 0.65

    /// Widest a single column may get before its content wraps. Each column may claim an
    /// equal share of the visible width, never less than the floor.
    private var maxColumnWidth: CGFloat {
        guard availableWidth > 0, table.columnCount > 0 else { return Self.minimumColumnCap }
        return max(availableWidth / CGFloat(table.columnCount), Self.minimumColumnCap)
    }

    private var lastColumn: Int {
        table.columnCount - 1
    }

    /// Inset of the outer columns from the card edge. The font's line-box inset is added to
    /// the standard spacing so it reads as even against the vertical padding. Derived from
    /// the body font so every row's left and right text edge lines up.
    private var outerColumnInset: CGFloat {
        Spacing.n16 + Typography.chatMessage.opticalInset
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            MarkdownTableLayout(
                columnCount: table.columnCount,
                maxColumnWidth: maxColumnWidth,
                minTableWidth: availableWidth
            ) {
                ForEach(Array(table.headers.enumerated()), id: \.offset) { column, header in
                    cell(
                        header,
                        column: column,
                        isHeader: true,
                        isFirstRow: true,
                        isLastRow: table.rows.isEmpty
                    )
                }
                ForEach(Array(table.rows.enumerated()), id: \.offset) { index, row in
                    ForEach(Array(row.enumerated()), id: \.offset) { column, text in
                        cell(
                            text,
                            column: column,
                            isHeader: false,
                            isFirstRow: table.headers.isEmpty && index == 0,
                            isLastRow: index == table.rows.count - 1
                        )
                    }
                }
            }
        }
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.containerSize.width
        } action: { _, width in
            availableWidth = width
        }
        // The feed owns vertical scrolling; without this the table's scroll view animates
        // its own resizing as content settles.
        .transaction { $0.animation = nil }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.surface.standard.elevated)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .tint(colors.accent)
    }

    /// One cell, its text inset from the edges. Outer columns and the first and last rows
    /// take a wider inset so text clears the card edges; interior edges share a gutter
    /// around the rules, which are overlaid on the padded frame so they run edge to edge.
    ///
    /// Fills the height the layout gives it, not its own: otherwise a one-line cell beside
    /// a wrapped one draws short and the column rule breaks partway down the row.
    private func cell(
        _ markdown: String,
        column: Int,
        isHeader: Bool,
        isFirstRow: Bool,
        isLastRow: Bool
    ) -> some View {
        Text(inline(markdown))
            .typography(isHeader ? Typography.miniLabel : Typography.chatMessage)
            .foregroundStyle(isHeader ? colors.text.standard.muted : colors.text.standard.base)
            .multilineTextAlignment(textAlignment(for: column))
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: contentAlignment(for: column)
            )
            .padding(.top, isFirstRow ? Spacing.n16 : Spacing.n8)
            .padding(.bottom, isLastRow ? Spacing.n16 : Spacing.n8)
            .padding(.leading, column == 0 ? outerColumnInset : Spacing.n12)
            .padding(.trailing, column == lastColumn ? outerColumnInset : Spacing.n12)
            .frame(maxHeight: .infinity)
            .overlay(alignment: .trailing) {
                if column != lastColumn {
                    rule.opacity(Self.faintRule).frame(width: 1)
                }
            }
            .overlay(alignment: .bottom) {
                if isHeader {
                    rule.opacity(Self.headerRule).frame(height: 1)
                } else if !isLastRow {
                    rule.opacity(Self.faintRule).frame(height: 1)
                }
            }
    }

    private var rule: some View {
        Rectangle().fill(colors.border.standard.base)
    }

    private func contentAlignment(for column: Int) -> Alignment {
        switch table.alignments[column] {
        case .leading: .topLeading
        case .center: .top
        case .trailing: .topTrailing
        }
    }

    private func textAlignment(for column: Int) -> TextAlignment {
        switch table.alignments[column] {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    /// Cells carry inline markdown only. Presentation intents resolve against the
    /// environment font, so bold and italic pick up the right serif faces.
    private func inline(_ markdown: String) -> AttributedString {
        (
            try? AttributedString(
                markdown: markdown,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            )
        ) ?? AttributedString(markdown)
    }
}

// MARK: - Previews

private struct TablePreview: View {
    @Environment(\.colors) private var colors

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.n24) {
                Text(verbatim: "Here's how the models compare on this workload:")
                    .typography(Typography.chatMessage)
                    .foregroundStyle(colors.text.standard.base)

                if let table = MarkdownTable.parse(Self.sample) {
                    MarkdownTableView(table: table)
                }

                if let table = MarkdownTable.parse(Self.wide) {
                    MarkdownTableView(table: table)
                }

                Text(verbatim: "Sonnet is the sensible default.")
                    .typography(Typography.chatMessage)
                    .foregroundStyle(colors.text.standard.base)
            }
            .padding(Spacing.n24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(colors.surface.standard.base)
    }

    static let sample = """
    | Model | Context | Cost | Speed |
    | :--- | ---: | ---: | :---: |
    | **Opus 5** | 200k | $$$ | Medium |
    | Sonnet 5 | 200k | $$ | Fast |
    | Haiku 4.5 | 200k | $ | Fastest |
    """

    /// Wider than the screen, with a long cell, to exercise scrolling, the column cap
    /// and wrapping.
    static let wide = """
    | Provider | Model | Context | Notes |
    |---|---|---:|---|
    | Anthropic | Opus 5 | 200k | Best for long agentic runs where quality matters more \
    than latency, and worth the cost when the task is genuinely hard |
    | Anthropic | Sonnet 5 | 200k | The sensible default |
    | Anthropic | Haiku 4.5 | 200k | Fast and cheap |
    """
}

#Preview("Light") {
    TablePreview()
        .resolveTheme()
}

#Preview("Dark") {
    TablePreview()
        .resolveTheme()
        .preferredColorScheme(.dark)
}
