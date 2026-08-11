@testable import Eigin
import Testing
#if canImport(UIKit)
import UIKit
#endif

/// Covers corner cases in the vendored markdown renderer that diverge from (or fix bugs
/// in) upstream SwiftStreamingMarkdown, plus Eigin's autolink addition. Not exhaustive —
/// extend as real model output surfaces more cases.
///
/// `---`-as-Setext-heading isn't covered here: `ContentBlock.split` (see
/// `ContentBlockTests`) always separates a divider into its own block before any text
/// reaches this parser, so it never sees a paragraph glued to a rule line. Fed raw, this
/// parser still treats `Text\n---` as a Setext heading, which is correct CommonMark.
@Suite("MarkdownParserImpl")
struct MarkdownParserTests {
    private let parser = MarkdownParserImpl()

    private func render(_ markdown: String) async -> RenderableDocument {
        await parser.parse(text: markdown, config: .default)
    }

    // MARK: - Block quotes

    @Test func blockQuoteKeepsNonParagraphChildren() async {
        let markdown = """
        > Intro line.
        >
        > - one
        > - two
        """
        let document = await render(markdown)
        guard case .blockQuote(_, let children) = document.renderables.first else {
            Issue.record("Expected a block quote")
            return
        }
        #expect(children.contains { if case .unorderedList = $0 { true } else { false } })
    }

    @Test func blockQuoteParagraphKeepsInlineFormatting() async {
        let markdown = "> This is **bold** text."
        let document = await render(markdown)
        guard case .blockQuote(_, let children) = document.renderables.first,
              case .paragraph(_, let content) = children.first
        else {
            Issue.record("Expected a block quote paragraph")
            return
        }
        let normalRange = (content.string as NSString).range(of: "This")
        let boldRange = (content.string as NSString).range(of: "bold")
        let normalFont = content.attribute(.font, at: normalRange.location, effectiveRange: nil)
        let boldFont = content.attribute(.font, at: boldRange.location, effectiveRange: nil)
        #expect(boldFont as? UIFont != normalFont as? UIFont)
    }

    // MARK: - Headings

    @Test func boldTextInAHeadingWithAnEmojiKeepsCorrectRanges() async {
        // Emoji are multi-UTF-16-code-unit; bold and plain text sitting either side of one
        // in the same heading is a real shape from AI-generated markdown, and a good check
        // that attribute ranges don't shift when a surrogate pair is in the mix.
        let markdown = "### \u{1F525} The **Big Question**"
        let document = await render(markdown)
        guard case .heading(_, let level, let content) = document.renderables.first else {
            Issue.record("Expected a heading")
            return
        }
        #expect(level == 3)
        #expect(content.string == "\u{1F525} The Big Question")

        let normalRange = (content.string as NSString).range(of: "The")
        let boldRange = (content.string as NSString).range(of: "Big Question")
        let normalFont = content.attribute(.font, at: normalRange.location, effectiveRange: nil)
        let boldFont = content.attribute(.font, at: boldRange.location, effectiveRange: nil)
        #expect(boldFont as? UIFont != normalFont as? UIFont)
    }

    // MARK: - A realistic composite document

    @Test func mixedContentWithNoBlankLinesBetweenBlocksRendersEveryBlock() async {
        // Genericized from a real AI-generated message that combined several
        // "technically valid, easy to get wrong" transitions in one document: a
        // paragraph interrupted by a list with no blank line, a triple-stacked divider
        // immediately followed by a bold+emoji heading, and a table with bold cells,
        // an em dash and smart quotes directly under a heading.
        let markdown = """
        Here's a summary:
        - **First point**: some detail.
        - **Second point**: more detail.

        ---
        ---
        ---
        ### \u{1F4A1} What stood out

        | **Did well** | **Could improve** |
        |---|---|
        | Answered clearly. | **Sharpen the pitch**\u{2014}lead with the objection. |
        """

        let blocks = ContentBlock.split(markdown, messageID: "test")
        #expect(blocks.contains { $0.kind == .paragraph })
        #expect(blocks.contains { $0.kind == .list })
        #expect(blocks.count(where: { $0.kind == .divider }) == 1)
        #expect(blocks.contains { $0.kind == .heading(level: 3) })
        #expect(blocks.contains { $0.kind == .table })

        guard let tableBlock = blocks.first(where: { $0.kind == .table }) else {
            Issue.record("Expected a table block")
            return
        }
        let table = MarkdownTable.parse(tableBlock.text)
        #expect(table?.headers == ["**Did well**", "**Could improve**"])
        #expect(table?.rows.first?.last?.contains("Sharpen the pitch") == true)

        let document = await render(tableBlock.text)
        #expect(document.renderables.contains { if case .table = $0 { true } else { false } })
    }

    // MARK: - Autolinks

    @Test func bareURLBecomesATappableLink() async {
        let markdown = "See https://example.com for more."
        let document = await render(markdown)
        guard case .paragraph(_, let content) = document.renderables.first else {
            Issue.record("Expected a paragraph")
            return
        }
        let urlRange = (content.string as NSString).range(of: "https://example.com")
        let link = content.attribute(.link, at: urlRange.location, effectiveRange: nil) as? URL
        #expect(link?.absoluteString == "https://example.com")
    }

    @Test func explicitLinkTextIsNotDoubleAutolinked() async {
        // `[text](url)` shouldn't also match the autolink detector over its own text.
        let markdown = "[https://example.com](https://example.com/other)"
        let document = await render(markdown)
        guard case .paragraph(_, let content) = document.renderables.first else {
            Issue.record("Expected a paragraph")
            return
        }
        let link = content.attribute(.link, at: 0, effectiveRange: nil) as? URL
        #expect(link?.absoluteString == "https://example.com/other")
    }

    // MARK: - Nested lists

    @Test func mixedNestedListsTrackNestingDepth() async {
        let markdown = """
        - one
          1. nested a
          2. nested b
        - two
        """
        let document = await render(markdown)
        guard case .unorderedList(_, let items, let topLevel) = document.renderables.first else {
            Issue.record("Expected an unordered list")
            return
        }
        #expect(topLevel == 0)

        let nestedList = items.first?.children.first { child in
            if case .orderedList = child { true } else { false }
        }
        guard case .orderedList(_, _, let nestedLevel) = nestedList else {
            Issue.record("Expected a nested ordered list")
            return
        }
        #expect(nestedLevel == 1)
    }

    @Test func blockQuoteNestedInsideAListItemStaysInTheListsText() async {
        // Regression: a block quote indented under a list item (itself nested under
        // another item) used to get split into its own paragraph block, stripped of the
        // indentation that placed it in the list. Fed to the renderer on its own, the
        // `>` no longer lined up as a quote marker and showed up as literal text.
        let markdown = """
        1. **Follow up with people**:
           - Send a **short email** recapping the key points:
             > *"Great conversation today. To recap:
             > - **Individuals will pay** for trust and control.
             > - **Organizations will adopt** because it solves a real need.
             > Let us know if you'd like to dive deeper.\"*
        """

        let blocks = ContentBlock.split(markdown, messageID: "test")
        #expect(blocks.count == 1)
        #expect(blocks.first?.kind == .list)

        let document = await render(markdown)
        guard case .orderedList(_, let items, _) = document.renderables.first,
              case .unorderedList(_, let subItems, _) = items.first?.children.last,
              let blockQuote = subItems.first?.children.last,
              case .blockQuote(_, let quoteChildren) = blockQuote
        else {
            Issue.record("Expected a block quote nested two list levels deep")
            return
        }
        #expect(quoteChildren.contains { if case .unorderedList = $0 { true } else { false } })
    }
}
