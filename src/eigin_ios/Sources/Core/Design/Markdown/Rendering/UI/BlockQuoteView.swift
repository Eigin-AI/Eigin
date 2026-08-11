import Foundation
import SwiftUI

/// Renders a block quote's content behind a leading bar. Content is arbitrary
/// block content (paragraphs, lists, nested quotes, ...), rendered through the
/// same dispatch as the rest of the document so nothing inside a quote is
/// dropped or flattened to plain text.
struct BlockQuoteView: View {
    let children: [MarkdownRenderable]

    var body: some View {
        HStack(spacing: 8.0) {
            QuoteDivider()
                .frame(width: 3.0)

            BlockView(renderables: children)
                .padding(.vertical, 4.0)
                .fixedSize(horizontal: false, vertical: true)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct QuoteDivider: View {
    @Environment(\.markdownConfig) var config: MarkdownRenderConfig

    var body: some View {
        RoundedRectangle(cornerRadius: 8.0, style: .continuous)
            .foregroundStyle(config.blockQuoteBarColor)
    }
}
