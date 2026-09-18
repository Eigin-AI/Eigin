@testable import Eigin
import Testing

@Suite("ContentBlock.split")
struct ContentBlockTests {
    private func split(_ text: String) -> [ContentBlock] {
        ContentBlock.split(text, messageID: "test")
    }

    // MARK: - Table detection

    @Test func compactSeparatorDetectedAsTable() {
        let markdown = """
        | A | B |
        |---|---|
        | 1 | 2 |
        """
        let blocks = split(markdown)
        #expect(blocks.count == 1)
        #expect(blocks[0].kind == .table)
        #expect(blocks[0].text.contains("| A | B |"))
        #expect(blocks[0].text.contains("|---|---|"))
        #expect(blocks[0].text.contains("| 1 | 2 |"))
    }

    @Test func spaciousSeparatorDetectedAsTable() {
        // Regression: "| -- | -- |" was not detected because spaces failed allSatisfy
        let markdown = """
        | A | B |
        | -- | -- |
        | 1 | 2 |
        """
        let blocks = split(markdown)
        #expect(blocks.count == 1)
        #expect(blocks[0].kind == .table)
    }

    @Test func spaciousSeparatorTableNewlinesPreserved() {
        // Regression: table rows were jammed together without newlines in the else branch
        let markdown = """
        | Use case | Narrative | Target persona |
        | -- | -- | -- |
        | Question 1 | | |
        | Question 2 | | |
        """
        let blocks = split(markdown)
        #expect(blocks.count == 1)
        #expect(blocks[0].kind == .table)
        // Each row must be on its own line
        let lines = blocks[0].text.components(separatedBy: "\n")
        #expect(lines.count == 4)
    }

    @Test func alignedSeparatorDetectedAsTable() {
        let markdown = """
        | Name | Value |
        | :--- | ---: |
        | foo  | 42   |
        """
        let blocks = split(markdown)
        #expect(blocks.count == 1)
        #expect(blocks[0].kind == .table)
    }

    @Test func consecutivePipeRowsWithoutSeparatorAreATable() {
        // Models often omit the header and its separator entirely.
        let blocks = split("""
        | Opus 5 | 200k |
        | Sonnet 5 | 200k |
        """)
        #expect(blocks.count == 1)
        #expect(blocks[0].kind == .table)
    }

    @Test func separatorFirstTableIsDetected() {
        let blocks = split("""
        |---|---|
        | Opus 5 | 200k |
        """)
        #expect(blocks.count == 1)
        #expect(blocks[0].kind == .table)
    }

    // MARK: - Table with surrounding content

    @Test func paragraphBeforeTable() {
        let markdown = """
        Here is a table:

        | A | B |
        |---|---|
        | 1 | 2 |
        """
        let blocks = split(markdown)
        #expect(blocks.count == 2)
        #expect(blocks[0].kind == .paragraph)
        #expect(blocks[1].kind == .table)
    }

    @Test func paragraphAfterTable() {
        let markdown = """
        | A | B |
        |---|---|
        | 1 | 2 |

        Some trailing text.
        """
        let blocks = split(markdown)
        #expect(blocks.count == 2)
        #expect(blocks[0].kind == .table)
        #expect(blocks[1].kind == .paragraph)
    }

    // MARK: - Dividers

    @Test func dashesUnderTextDrawARuleNotASetextHeading() {
        // Headings are ATX-only; a `---` line is always a divider, even directly
        // under paragraph text — never read as a Setext heading underline.
        let markdown = """
        Section title
        ---

        Body text.
        """
        let blocks = split(markdown)
        #expect(blocks.contains { $0.kind == .divider })
        #expect(blocks[0].text == "Section title")
        #expect(blocks[0].kind == .paragraph)
    }

    @Test func dashesAfterBlankLineDrawARule() {
        let markdown = """
        Some text.

        ---

        More text.
        """
        let blocks = split(markdown)
        #expect(blocks.contains { $0.kind == .divider })
    }

    @Test func starRuleUnderTextStillDrawsARule() {
        // Only dashes underline a setext heading; `***` is always a thematic break.
        let markdown = """
        Some text.
        ***
        """
        let blocks = split(markdown)
        #expect(blocks.contains { $0.kind == .divider })
    }

    @Test func leadingRuleDrawsARule() {
        let blocks = split("---\n\nText.")
        #expect(blocks.contains { $0.kind == .divider })
    }

    @Test func stackedRulesCollapseToOneDivider() {
        let blocks = split("""
        Some text.

        ---
        ---
        ---

        More text.
        """)
        #expect(blocks.count(where: { $0.kind == .divider }) == 1)
    }

    @Test func rulesSeparatedByBlankLinesCollapse() {
        let blocks = split("""
        A

        ---

        ---

        B
        """)
        #expect(blocks.count(where: { $0.kind == .divider }) == 1)
    }

    @Test func rulesWithContentBetweenKeepBothDividers() {
        let blocks = split("""
        ---

        text

        ---
        """)
        #expect(blocks.count(where: { $0.kind == .divider }) == 2)
    }

    @Test func ruleImmediatelyAfterAListDrawsADivider() {
        // Caught as our divider rather than becoming paragraph text the library rules.
        let blocks = split("""
        - one
        - two
        ---
        After.
        """)
        #expect(blocks.contains { $0.kind == .list })
        #expect(blocks.count(where: { $0.kind == .divider }) == 1)
        #expect(blocks.contains { $0.kind == .paragraph && $0.text.contains("After") })
    }

    // MARK: - Code fenced inside a list

    @Test func codeFenceInsideAListBecomesItsOwnCodeBlock() {
        // Regression: the fence used to be swallowed into a paragraph, its closing
        // fence then opened a second block that ate the rest of the message.
        let blocks = split("""
        1. First, run the build:

            ```bash
            just build ios
            ```

        2. Then check the output.
        """)
        let code = blocks.filter { $0.kind == .code }
        #expect(code.count == 1)
        #expect(code[0].text == "just build ios")
        #expect(code[0].language == "bash")
        // The trailing step must survive as its own content, not be eaten as code.
        #expect(blocks.contains { $0.kind == .list && $0.text.contains("Then check") })
    }

    @Test func codeFenceDirectlyUnderAListLineEndsTheList() {
        // No blank line between the list item and the fence, so the list is still open
        // when the fence arrives. It must end the list rather than absorb the fence.
        let blocks = split("""
        1. Run this:
           ```bash
           just build ios
           ```
        """)
        let code = blocks.filter { $0.kind == .code }
        #expect(code.count == 1)
        #expect(code[0].text == "just build ios")
        #expect(code[0].language == "bash")
        #expect(blocks.contains { $0.kind == .list })
    }

    @Test func indentedCodeInsideAListIsDedented() {
        let blocks = split("""
        - Example:

            ```swift
            let x = 1
            ```
        """)
        let code = blocks.first { $0.kind == .code }
        #expect(code?.text == "let x = 1")
    }

    @Test func codeAfterAListStillSealsCorrectly() {
        // The message doesn't run away as one giant code block: exactly one code block,
        // and prose after the fence stays prose.
        let blocks = split("""
        Steps:

        1. Do this
        2. Do that

        ```
        result
        ```

        All done.
        """)
        #expect(blocks.count(where: { $0.kind == .code }) == 1)
        #expect(blocks.contains { $0.kind == .paragraph && $0.text.contains("All done") })
    }

    // MARK: - ATX headings

    @Test func parsesEachHeadingLevel() {
        for level in 1 ... 6 {
            let hashes = String(repeating: "#", count: level)
            let blocks = split("\(hashes) Title")
            #expect(blocks.count == 1)
            #expect(blocks[0].kind == .heading(level: level))
            #expect(blocks[0].text == "Title")
        }
    }

    @Test func hashWithoutSpaceIsNotAHeading() {
        let blocks = split("#tag is not a heading")
        #expect(blocks.allSatisfy { if case .heading = $0.kind { false } else { true } })
    }

    @Test func sevenHashesIsNotAHeading() {
        let blocks = split("####### too deep")
        #expect(blocks.allSatisfy { if case .heading = $0.kind { false } else { true } })
    }

    @Test func headingInterruptsParagraph() {
        let blocks = split("""
        Some intro text.
        ## Section
        """)
        #expect(blocks.count == 2)
        #expect(blocks[0].kind == .paragraph)
        #expect(blocks[1].kind == .heading(level: 2))
        #expect(blocks[1].text == "Section")
    }

    @Test func dropsClosingHashSequence() {
        let blocks = split("## Title ##")
        #expect(blocks[0].kind == .heading(level: 2))
        #expect(blocks[0].text == "Title")
    }

    @Test func headingKeepsInlineMarkdown() {
        let blocks = split("# The **bold** truth")
        #expect(blocks[0].kind == .heading(level: 1))
        #expect(blocks[0].text == "The **bold** truth")
    }

    @Test func headingAfterAListEndsTheList() {
        let blocks = split("""
        - one
        - two
        # After
        """)
        #expect(blocks.contains { $0.kind == .list })
        #expect(blocks.contains { $0.kind == .heading(level: 1) })
    }

    // MARK: - Adjacent blocks with no blank line between them

    @Test func listInterruptsAParagraphWithoutABlankLine() {
        // CommonMark: an unordered list can interrupt a paragraph with no blank line
        // (unlike a heading, which always can, or an ordered list, which can only
        // interrupt if it starts at 1).
        let blocks = split("""
        Some lead-in text:
        - one
        - two
        """)
        #expect(blocks.contains { $0.kind == .paragraph && $0.text.contains("lead-in") })
        #expect(blocks.contains { $0.kind == .list })
    }

    @Test func headingImmediatelyAfterStackedDividersWithNoBlankLine() {
        let blocks = split("""
        Some text.
        ---
        ---
        ---
        # Heading
        """)
        #expect(blocks.count(where: { $0.kind == .divider }) == 1)
        #expect(blocks.contains { $0.kind == .heading(level: 1) })
    }

    @Test func tableImmediatelyAfterHeadingWithNoBlankLine() {
        let blocks = split("""
        # Heading
        | A | B |
        |---|---|
        | 1 | 2 |
        """)
        #expect(blocks.contains { $0.kind == .heading(level: 1) })
        #expect(blocks.contains { $0.kind == .table })
    }

    // MARK: - Edge cases

    @Test func emptyRowDoesNotFalsePositiveSeparator() {
        // "|  |" should not be treated as a table separator
        let markdown = """
        Some text
        |  |
        More text
        """
        let blocks = split(markdown)
        // Should not produce a table block
        #expect(blocks.allSatisfy { $0.kind != .table })
    }
}

// MARK: - Standalone images

@Suite("ContentBlock.split images")
struct ContentBlockImageTests {
    private func split(_ text: String) -> [ContentBlock] {
        ContentBlock.split(text, messageID: "test")
    }

    @Test func loneImageBecomesAnImageBlock() {
        let blocks = split("![A sunset over the bay](https://example.com/sunset.jpg)")
        #expect(blocks.count == 1)
        #expect(blocks[0].kind == .image(
            src: "https://example.com/sunset.jpg",
            alt: "A sunset over the bay",
            href: nil
        ))
    }

    @Test func imageWithoutAltParsesNilAlt() {
        // An empty alt is no caption: nil, not an empty string.
        let blocks = split("![](https://example.com/photo.png)")
        #expect(blocks.count == 1)
        if case .image(let src, let alt, let href) = blocks[0].kind {
            #expect(src == "https://example.com/photo.png")
            #expect(alt == nil)
            #expect(href == nil)
        } else {
            Issue.record("expected an image block")
        }
    }

    @Test func linkedImageCarriesItsHref() {
        let blocks =
            split(
                "[![Chart of latency](https://example.com/chart.png)](https://example.com/report)"
            )
        #expect(blocks.count == 1)
        if case .image(let src, let alt, let href) = blocks[0].kind {
            #expect(src == "https://example.com/chart.png")
            #expect(alt == "Chart of latency")
            #expect(href == "https://example.com/report")
        } else {
            Issue.record("expected an image block")
        }
    }

    @Test func imageInsideASentenceStaysInline() {
        let blocks = split("Here is a photo ![sunset](https://example.com/s.jpg) from the trip.")
        #expect(blocks.count == 1)
        #expect(blocks[0].kind == .paragraph)
        #expect(blocks[0].text.contains("![sunset](https://example.com/s.jpg)"))
    }

    @Test func imageBetweenParagraphsSplitsAllThree() {
        let blocks = split("""
        Look at this:

        ![sunset](https://example.com/s.jpg)

        And that was that.
        """)
        #expect(blocks.count == 3)
        #expect(blocks[0].kind == .paragraph)
        #expect(blocks[1].kind == .image(
            src: "https://example.com/s.jpg",
            alt: "sunset",
            href: nil
        ))
        #expect(blocks[2].kind == .paragraph)
    }

    @Test func imageDirectlyAfterTextEndsTheParagraph() {
        let blocks = split("First line\n![sunset](https://example.com/s.jpg)")
        #expect(blocks.count == 2)
        #expect(blocks[0].kind == .paragraph)
        #expect(blocks[1].kind == .image(
            src: "https://example.com/s.jpg",
            alt: "sunset",
            href: nil
        ))
    }

    @Test func imageInAFencedCodeBlockStaysCode() {
        let blocks = split("""
        Like this:

        ```
        ![not an image](https://example.com/s.jpg)
        ```
        """)
        #expect(blocks.count == 2)
        #expect(blocks[1].kind == .code)
        #expect(blocks.allSatisfy { if case .image = $0.kind { false } else { true } })
    }

    @Test func indentedImageIsNotAStandaloneBlock() {
        // A list-indented image belongs to the list's text, not the feed.
        let blocks = split("""
        - item one
          ![sunset](https://example.com/s.jpg)
        """)
        #expect(blocks.count == 1)
        #expect(blocks[0].kind == .list)
    }
}

// MARK: - Streaming image holdback

@Suite("ContentBlock.split streaming holdback")
struct ContentBlockStreamingTests {
    private func split(_ text: String, streaming: Bool) -> [ContentBlock] {
        ContentBlock.split(text, messageID: "test", isStreaming: streaming)
    }

    @Test func partialImageIsWithheldWhileStreaming() {
        let blocks = split("Here's a photo:\n\n![sunset](https://example.com/sun", streaming: true)
        // The prose survives; the half-formed image line is nowhere.
        #expect(blocks.allSatisfy { $0.kind == .paragraph })
        // Interrupted paragraphs trail the blank line's newline; the prose itself is intact.
        #expect(blocks[0].text.trimmingCharacters(in: .whitespacesAndNewlines) == "Here's a photo:")
        #expect(blocks.count == 1)
        #expect(blocks.allSatisfy { !$0.text.contains("![sunset]") })
    }

    @Test func imageThatClosedOnALaterChunkRendersWhileStreaming() {
        let blocks = split("![sunset](https://example.com/sun.jpg)", streaming: true)
        #expect(blocks.count == 1)
        #expect(blocks[0].kind == .image(
            src: "https://example.com/sun.jpg",
            alt: "sunset",
            href: nil
        ))
    }

    @Test func withheldCandidateHasProvenanceWhenComplete() {
        let streaming = split("![sunset](https://example.com/s", streaming: true)
        let complete = split("![sunset](https://example.com/s.jpg)", streaming: true)
        #expect(streaming.count == 0)
        #expect(complete.count == 1)
        #expect(complete[0].kind == .image(
            src: "https://example.com/s.jpg",
            alt: "sunset",
            href: nil
        ))
    }

    @Test func malformedImageShowsAsRawTextOnceTheTurnEnds() {
        let blocks = split("![sunset](https://example.com/s", streaming: false)
        #expect(blocks.count == 1)
        #expect(blocks[0].kind == .paragraph)
        #expect(blocks[0].text == "![sunset](https://example.com/s")
    }

    @Test func candidateThatClosesOnTheNextLineBecomesAnImage() {
        // Chunk boundary split the line: first call holds, later call closes.
        let held = split("![sunset](https://example.com/sun", streaming: true)
        let closed = split(
            "![sunset](https://example.com/sun.jpg)\n\nWhat a view.",
            streaming: true
        )
        #expect(held.count == 0)
        #expect(closed.count == 2)
        #expect(closed[0].kind == .image(
            src: "https://example.com/sun.jpg",
            alt: "sunset",
            href: nil
        ))
        #expect(closed[1].kind == .paragraph)
    }

    @Test func neverClosingCandidateShowsRawMarkdownOnceTheNextLineArrives() {
        // Multiline images aren't supported: a second line proves it wasn't one.
        let blocks = split(
            "![sunset is a nice pic\nof the bay](https://example.com/x.jpg)",
            streaming: true
        )
        #expect(blocks.allSatisfy { $0.kind == .paragraph })
        #expect(blocks[0].text.contains("![sunset is a nice pic"))
    }

    @Test func referenceStyleImageFallsBackToProse() {
        let held = split("![alt][ref]", streaming: true)
        let done = split("![alt][ref]", streaming: false)
        #expect(held.count == 0)
        #expect(done.count == 1)
        #expect(done[0].text == "![alt][ref]")
    }

    @Test func twoImagesBackToBackBothRender() {
        let blocks = split(
            "![a](https://example.com/a.jpg)\n![b](https://example.com/b.jpg)",
            streaming: true
        )
        let images = blocks.filter {
            if case .image = $0.kind { true } else { false }
        }
        #expect(images.count == 2)
    }

    @Test func linkedImageStreamingHoldsThenRenders() {
        let held = split("[![alt](https://example.com/a.jpg)](htt", streaming: true)
        let closed = split(
            "[![alt](https://example.com/a.jpg)](https://example.com)",
            streaming: true
        )
        #expect(held.count == 0)
        if case .image(let src, let alt, let href) = closed[0].kind {
            #expect(src == "https://example.com/a.jpg")
            #expect(alt == "alt")
            #expect(href == "https://example.com")
        } else {
            Issue.record("expected an image block")
        }
    }
}

// MARK: - URL shapes in image markdown

@Suite("ContentBlock.split image URL shapes")
struct ContentBlockImageURLTests {
    private func split(_ text: String, streaming: Bool = false) -> [ContentBlock] {
        ContentBlock.split(text, messageID: "test", isStreaming: streaming)
    }

    @Test func balancedParensInURLStayWhole() {
        let url = "https://en.wikipedia.org/wiki/Cat_(disambiguation)"
        let blocks = split("![A cat](\(url))")
        #expect(blocks.count == 1)
        #expect(blocks[0].kind == .image(src: url, alt: "A cat", href: nil))
    }

    @Test func balancedParensInLinkedURLs() {
        let src = "https://en.wikipedia.org/wiki/Cat_(disambiguation)"
        let href = "https://en.wikipedia.org/wiki/Cat_(disambiguation)#Gallery"
        let blocks = split("[![A cat](\(src))](\(href))")
        #expect(blocks.count == 1)
        #expect(blocks[0].kind == .image(src: src, alt: "A cat", href: href))
    }

    @Test func trailingTextAfterTheParenIsNotAnImage() {
        let blocks = split("![a](https://example.com/x.jpg) and more text", streaming: false)
        #expect(blocks.count == 1)
        #expect(blocks[0].kind == .paragraph)
    }

    @Test func streamingHoldAdmitsUrlsWithParens() {
        let url = "https://en.wikipedia.org/wiki/Cat_(disambiguation)"
        #expect(split("![a](" + url, streaming: true).count == 0)
        #expect(split("![a](" + url + ")", streaming: true).count == 1)
    }
}
