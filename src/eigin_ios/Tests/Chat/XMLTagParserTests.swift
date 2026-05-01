@testable import Eigin
import Testing

@Suite("XMLTagParser")
struct XMLTagParserTests {
    @Test func extractsValueAndReason() {
        let output = #"<name reason="User said their name was Daniel">Daniel</name>"#
        let result = XMLTagParser.extract(tag: "name", from: output)
        #expect(result == .extracted(value: "Daniel", reason: "User said their name was Daniel"))
    }

    @Test func extractsValueWithoutReason() {
        let output = "<name>Tracy</name>"
        let result = XMLTagParser.extract(tag: "name", from: output)
        #expect(result == .extracted(value: "Tracy", reason: nil))
    }

    @Test func trimsWhitespaceFromValue() {
        let output = "<name reason=\"test\">  Matt  </name>"
        let result = XMLTagParser.extract(tag: "name", from: output)
        #expect(result == .extracted(value: "Matt", reason: "test"))
    }

    @Test func returnsNoMatchWhenTagAbsent() {
        let output = "NONE"
        let result = XMLTagParser.extract(tag: "name", from: output)
        if case .noMatch(let raw) = result {
            #expect(raw == "NONE")
        } else {
            Issue.record("Expected .noMatch, got \(result)")
        }
    }

    @Test func returnsEmptyForBlankOutput() {
        #expect(XMLTagParser.extract(tag: "name", from: "") == .empty)
        #expect(XMLTagParser.extract(tag: "name", from: "   \n  ") == .empty)
    }

    @Test func returnsNoMatchForMalformedTagNoClose() {
        let output = "<name reason=\"test\">Daniel"
        let result = XMLTagParser.extract(tag: "name", from: output)
        if case .noMatch = result {
            // Expected
        } else {
            Issue.record("Expected .noMatch for malformed tag, got \(result)")
        }
    }

    @Test func takesLastOccurrenceWhenMultipleTags() {
        // Simulates a model that echoes a few-shot example before producing its own answer
        let output = """
        <name reason="Example">Matt</name>
        <name reason="User said people call me Daniel">Daniel</name>
        """
        let result = XMLTagParser.extract(tag: "name", from: output)
        #expect(result == .extracted(value: "Daniel", reason: "User said people call me Daniel"))
    }

    @Test func handlesSingleQuoteReason() {
        let output = "<name reason='single quotes'>Alex</name>"
        let result = XMLTagParser.extract(tag: "name", from: output)
        #expect(result == .extracted(value: "Alex", reason: "single quotes"))
    }

    @Test func handlesEmptyReasonAttribute() {
        let output = #"<name reason="">Jordan</name>"#
        let result = XMLTagParser.extract(tag: "name", from: output)
        // Empty reason string is treated as nil
        #expect(result == .extracted(value: "Jordan", reason: nil))
    }

    @Test func worksWithDifferentTagNames() {
        let output = #"<preference reason="User chose sparring partner">Sparring partner</preference>"#
        let result = XMLTagParser.extract(tag: "preference", from: output)
        #expect(result == .extracted(
            value: "Sparring partner",
            reason: "User chose sparring partner"
        ))
    }

    @Test func handlesSelfClosingTagWithReason() {
        let output = #"<style reason="The user indicated a preference for a casual tone."/>"#
        let result = XMLTagParser.extract(tag: "style", from: output)
        #expect(result == .extracted(
            value: "",
            reason: "The user indicated a preference for a casual tone."
        ))
    }

    @Test func handlesSelfClosingTagWithoutReason() {
        let output = "<style/>"
        let result = XMLTagParser.extract(tag: "style", from: output)
        #expect(result == .extracted(value: "", reason: nil))
    }
}
