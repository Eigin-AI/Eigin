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
