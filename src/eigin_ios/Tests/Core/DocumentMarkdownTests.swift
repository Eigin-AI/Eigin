@testable import Eigin
import Testing

@Suite("Document Markdown")
struct DocumentMarkdownTests {
    @Test func preservesSurroundingProseAndReplacesTableExactlyOnce() {
        let result = DocumentMarkdown.render(
            transcript: "Invoice\nItem\nTotal\nHosting\n25.00\nThank you",
            tables: [[["Item", "Total"], ["Hosting", "25.00"]]]
        )
        #expect(result ==
            "Invoice\n| Item | Total |\n| --- | --- |\n| Hosting | 25.00 |\nThank you")
    }

    @Test func escapesMarkdownAndMultilineCells() {
        let result = DocumentMarkdown.render(
            transcript: "Description\nA|B\\C\nSecond line",
            tables: [[["Description"], ["A|B\\C\nSecond line"]]]
        )
        #expect(result == "| Description |\n| --- |\n| A\\|B\\\\C<br>Second line |")
    }

    @Test func preservesTextWhenTableSpanDoesNotMatch() {
        let transcript = "Item Total\nHosting 25.00"
        #expect(DocumentMarkdown.render(
            transcript: transcript,
            tables: [[["Item", "Total"], ["Hosting", "25.00"]]]
        ) == transcript)
    }

    @Test func rendersMultipleTablesWithoutLosingInterveningText() {
        #expect(DocumentMarkdown.render(
            transcript: "First\n1\nBetween\nSecond\n2\nEnd",
            tables: [[["First"], ["1"]], [["Second"], ["2"]]]
        ) == "| First |\n| --- |\n| 1 |\nBetween\n| Second |\n| --- |\n| 2 |\nEnd")
    }

    @Test func ignoresEmptyTablesAndEmptyTranscripts() {
        #expect(DocumentMarkdown
            .render(transcript: "Keep this", tables: [[], [[]], [[""]]]) == "Keep this")
        #expect(DocumentMarkdown.render(transcript: "", tables: [[["Header"]]]) == "")
    }

    @Test func keepsEmptyCellsInMatchedTables() {
        #expect(DocumentMarkdown.render(
            transcript: "Name\nValue\nEmpty\n",
            tables: [[["Name", "Value"], ["Empty", ""]]]
        ) == "| Name | Value |\n| --- | --- |\n| Empty |  |")
    }
}
