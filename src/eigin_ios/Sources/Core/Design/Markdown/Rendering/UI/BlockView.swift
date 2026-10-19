import Foundation
import SwiftUI

struct BlockView: View {
    @Environment(\.markdownConfig) var config: MarkdownRenderConfig

    let renderables: [MarkdownRenderable]

    init(renderables: [MarkdownRenderable]) {
        self.renderables = renderables
    }

    var body: some View {
        VStack(alignment: .leading, spacing: config.blockSpacing) {
            ForEach(renderables) { renderable in
                SingleBlockView(renderable: renderable)
            }
        }
    }
}

struct SingleBlockView: View {
    @Environment(\.markdownConfig) var config: MarkdownRenderConfig

    let renderable: MarkdownRenderable

    init(renderable: MarkdownRenderable) {
        self.renderable = renderable
    }

    var body: some View {
        Group {
            switch renderable {
            case .heading(_, _, let contents):
                ParagraphView(contents: contents)
                    .transition(.opacity)
                    .accessibilityAddTraits(.isHeader)
            case .paragraph(_, let contents):
                ParagraphView(contents: contents)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            case .latex(_, let latexString):
                ScrollView(.horizontal) {
                    HStack(spacing: 0) {
                        BlockMathView(latex: latexString, color: config.paragraphStyle.textColor)
                        Spacer()
                    }
                }.scrollIndicators(.hidden)
            case .orderedList(_, let items, let nestedLevel):
                OrderedListView(items: items, nestedLevel: nestedLevel)
            case .unorderedList(_, let items, let nestedLevel):
                UnorderedListView(items: items, nestedLevel: nestedLevel)
            case .codeBlock(_, _, let code):
                // Code blocks are split out to EiginCodeBlock upstream; this only
                // fires on odd fallbacks, so render the raw text as a paragraph.
                ParagraphView(contents: plainParagraph(code))
                    .fixedSize(horizontal: false, vertical: true)
            case .thematicBreak:
                ThematicBreakView()
            case .table(_, _, _, let rawMarkdown):
                // Tables are handled by MarkdownTableView upstream; a malformed table
                // that falls back here degrades to its raw text rather than vanishing.
                ParagraphView(contents: plainParagraph(rawMarkdown))
                    .fixedSize(horizontal: false, vertical: true)
            case .blockQuote(_, let children):
                BlockQuoteView(children: children)
            }
        }
    }

    /// Builds a plain paragraph attributed string styled with the paragraph
    /// config, used for off-path block kinds that fall back to text.
    private func plainParagraph(_ text: String) -> NSMutableAttributedString {
        NSMutableAttributedString(
            string: text,
            attributes: config.paragraphStyle.plainTextAttributes
        )
    }
}
