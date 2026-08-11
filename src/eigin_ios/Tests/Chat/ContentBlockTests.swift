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
