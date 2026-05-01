import SwiftUI
import Textual

/// Renders markdown as a code block with styling consistent with chat messages.
struct DetailCodeBlock: View {
    let markdown: String

    @Environment(\.colors) private var colors

    var body: some View {
        StructuredText(markdown: markdown)
            .foregroundStyle(colors.textPrimary)
            .textual.textSelection(.enabled)
    }
}
