import SwiftUI
import Textual

/// Renders a code block with syntax highlighting and horizontal scrolling.
struct DetailCodeBlock: View {
    let code: String
    var language: String?
    /// When false, uses the `.plain` highlighter theme, which skips the syntax
    /// tokenizer entirely. Set false while the block is still streaming so we don't
    /// re-tokenize on every chunk.
    var highlightSyntax: Bool = true

    @Environment(\.colors) private var colors

    private var markdown: String {
        let fence = language ?? ""
        return "```\(fence)\n\(code)\n```"
    }

    var body: some View {
        StructuredText(markdown: markdown)
            .font(Typography.code.font)
            .foregroundStyle(colors.text.standard.base)
            .tint(colors.accent)
            .eiginStructuredText(colors: colors, highlightSyntax: highlightSyntax)
    }
}
