import SwiftUI
import Textual

struct ContentBlockView: View {
    let block: ContentBlock
    /// True only for the block currently being streamed (the last block of a live
    /// message). An actively-streaming table renders as a raw markdown code block to
    /// avoid the expensive table relayout on every chunk; once the block is sealed
    /// (a later block starts, or the turn finishes) it renders as a real table.
    var isActivelyStreaming: Bool = false

    @Environment(\.colors) private var colors

    var body: some View {
        switch block.kind {
        case .divider:
            Divider()
                .background(colors.text.standard.muted.opacity(0.3))
                .padding(.vertical, Spacing.n4)
        case .code:
            DetailCodeBlock(
                code: block.text,
                language: block.language,
                highlightSyntax: !isActivelyStreaming
            )
        case .table where isActivelyStreaming:
            DetailCodeBlock(code: block.text, language: "markdown", highlightSyntax: false)
        default:
            StructuredText(markdown: block.text, syntaxExtensions: [])
                .font(Typography.chatMessage.font)
                .foregroundStyle(colors.text.standard.base)
                .tint(colors.accent)
                .eiginStructuredText(colors: colors)
                .textual.tableStyle(.overflow(relativeWidth: 3))
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 16) {
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
                text: "func hello() {\n    print(\"world\")\n}"
            )
        )

        ContentBlockView(
            block: ContentBlock(id: "4", kind: .table, text: "| A | B |\n|---|---|\n| 1 | 2 |")
        )
    }
    .padding()
}
