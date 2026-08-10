@testable import Eigin
import Testing

@Suite("MarkdownTable.parse")
struct MarkdownTableTests {
    @Test func parsesHeadersAndRows() {
        let table = MarkdownTable.parse("""
        | Model | Context |
        |---|---|
        | Opus 5 | 200k |
        | Sonnet 5 | 200k |
        """)
        #expect(table?.headers == ["Model", "Context"])
        #expect(table?.rows == [["Opus 5", "200k"], ["Sonnet 5", "200k"]])
    }

    @Test func readsColumnAlignments() {
        let table = MarkdownTable.parse("""
        | L | C | R | D |
        | :--- | :---: | ---: | --- |
        | a | b | c | d |
        """)
        #expect(table?.alignments == [.leading, .center, .trailing, .leading])
    }

    @Test func padsShortRowsAndTruncatesLongOnes() {
        let table = MarkdownTable.parse("""
        | A | B |
        |---|---|
        | only |
        | one | two | three |
        """)
        #expect(table?.rows == [["only", ""], ["one", "two"]])
    }

    @Test func keepsEscapedPipesInsideCells() {
        let table = MarkdownTable.parse("""
        | Expression | Meaning |
        |---|---|
        | a \\| b | or |
        """)
        #expect(table?.rows == [["a | b", "or"]])
    }

    @Test func keepsInlineMarkdownForTheRenderer() {
        let table = MarkdownTable.parse("""
        | Name |
        |---|
        | **bold** and `code` |
        """)
        #expect(table?.rows == [["**bold** and `code`"]])
    }

    @Test func parsesRowsWithoutOuterPipes() {
        let table = MarkdownTable.parse("""
        Model | Context
        --- | ---
        Opus 5 | 200k
        """)
        #expect(table?.headers == ["Model", "Context"])
        #expect(table?.rows == [["Opus 5", "200k"]])
    }

    @Test func headerOnlyTableParsesWithNoRows() {
        let table = MarkdownTable.parse("""
        | A | B |
        |---|---|
        """)
        #expect(table?.headers == ["A", "B"])
        #expect(table?.rows.isEmpty == true)
    }

    // MARK: - Missing header row

    @Test func parsesTableThatOmitsItsHeader() {
        let table = MarkdownTable.parse("""
        |---|---:|
        | Opus 5 | 200k |
        | Sonnet 5 | 200k |
        """)
        #expect(table?.headers.isEmpty == true)
        #expect(table?.alignments == [.leading, .trailing])
        #expect(table?.rows == [["Opus 5", "200k"], ["Sonnet 5", "200k"]])
    }

    @Test func parsesBareRowsWithNoHeaderOrSeparator() {
        let table = MarkdownTable.parse("""
        | Opus 5 | 200k |
        | Sonnet 5 | 200k |
        """)
        #expect(table?.headers.isEmpty == true)
        #expect(table?.columnCount == 2)
        #expect(table?.rows == [["Opus 5", "200k"], ["Sonnet 5", "200k"]])
    }

    @Test func aDataRowContainingDashesIsNotASeparator() {
        let table = MarkdownTable.parse("""
        | Range | Note |
        | 1-2 | --- |
        | 3-4 | ok |
        """)
        // The second line has one valid spec and one that isn't, so it's a data row and
        // the table has no header.
        #expect(table?.headers.isEmpty == true)
        #expect(table?.rows.count == 3)
    }

    // MARK: - Rejection

    @Test func rejectsASinglePipeRow() {
        // One row is a sentence with a pipe in it as easily as it is a table.
        #expect(MarkdownTable.parse("| A | B |") == nil)
    }

    @Test func rejectsSeparatorWithWrongColumnCount() {
        #expect(MarkdownTable.parse("| A | B |\n|---|\n| 1 | 2 |") == nil)
    }

    @Test func rejectsNonTableText() {
        #expect(MarkdownTable.parse("Just a sentence.") == nil)
    }

    @Test func rejectsProseEvenAcrossTwoLines() {
        #expect(MarkdownTable.parse("Press Cmd | Q to quit.\nThen relaunch.") == nil)
    }
}
