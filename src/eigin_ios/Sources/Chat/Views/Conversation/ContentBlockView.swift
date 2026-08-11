import SwiftUI

struct ContentBlockView: View, Equatable {
    let block: ContentBlock
    /// True for the block currently streaming (the last block of a live message).
    var isActivelyStreaming: Bool = false

    @Environment(\.colors) private var colors

    /// Lets `.equatable()` skip re-rendering blocks that haven't changed while streaming.
    nonisolated static func == (lhs: ContentBlockView, rhs: ContentBlockView) -> Bool {
        lhs.block == rhs.block && lhs.isActivelyStreaming == rhs.isActivelyStreaming
    }

    /// Extra vertical margin on the hard-edged cards (code, tables) so they sit with the
    /// same visual rhythm as text blocks, which carry the font's line-box leading the cards
    /// don't. Without it a card reads tighter against a heading or paragraph than two text
    /// blocks read against each other.
    private var cardSpacing: CGFloat {
        Typography.chatMessage.lineBoxInset
    }

    var body: some View {
        switch block.kind {
        case .heading(let level):
            MarkdownHeadingView(level: level, text: block.text)
        case .divider:
            Divider()
                .background(colors.text.standard.muted.opacity(0.3))
                .padding(.vertical, Spacing.n4)
        case .code:
            EiginCodeBlock(
                code: block.text,
                language: block.language,
                isStreaming: isActivelyStreaming
            )
            .padding(.vertical, cardSpacing)
        case .table:
            // A block that doesn't parse as a table falls back to the markdown renderer.
            if let table = MarkdownTable.parse(block.text) {
                MarkdownTableView(table: table)
                    .padding(.vertical, cardSpacing)
            } else {
                MarkdownBlockView(text: block.text)
            }
        case .math:
            // The block already holds pure LaTeX; render it directly.
            MathBlockView(latex: block.text)
        default:
            MarkdownBlockView(text: block.text)
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: Spacing.n16) {
        ContentBlockView(
            block: ContentBlock(id: "1", kind: .paragraph, text: "This is a paragraph.")
        )

        ContentBlockView(
            block: ContentBlock(id: "2", kind: .divider, text: "")
        )

        ContentBlockView(
            block: ContentBlock(
                id: "3",
                kind: .code,
                text: "func hello() {\n    print(\"world\")\n}",
                language: "swift"
            )
        )

        ContentBlockView(
            block: ContentBlock(id: "4", kind: .table, text: "| A | B |\n|---|---|\n| 1 | 2 |")
        )
    }
    .padding()
    .resolveTheme()
}
