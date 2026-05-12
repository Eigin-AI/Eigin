import SwiftUI
import Textual

struct ContentBlockView: View {
    let block: ContentBlock

    @Environment(\.colors) private var colors

    var body: some View {
        switch block.kind {
        case .divider:
            Divider()
                .background(colors.textSecondary.opacity(0.3))
                .padding(.vertical, Spacing.xs)
        case .code:
            DetailCodeBlock(code: block.text, language: block.language)
        default:
            StructuredText(markdown: block.text, syntaxExtensions: [])
                .font(Typography.body.font)
                .foregroundStyle(colors.textPrimary)
                .tint(colors.accent)
                .textual.inlineStyle(.eigin(colors: colors))
                .textual.headingStyle(EiginHeadingStyle())
                .textual.highlighterTheme(.default)
                .textual.textSelection(.enabled)
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
