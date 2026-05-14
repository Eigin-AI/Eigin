import SwiftUI
import Textual

/// Renders a code block with syntax highlighting and horizontal scrolling.
struct DetailCodeBlock: View {
    let code: String
    var language: String?

    @Environment(\.colors) private var colors

    private var markdown: String {
        let fence = language ?? ""
        return "```\(fence)\n\(code)\n```"
    }

    var body: some View {
        StructuredText(markdown: markdown)
            .font(Typography.body.font)
            .foregroundStyle(colors.text.standard.base)
            .tint(colors.accent)
            .textual.inlineStyle(.eigin(colors: colors))
            .textual.headingStyle(EiginHeadingStyle())
            .textual.highlighterTheme(.default)
            .textual.textSelection(.enabled)
    }
}
