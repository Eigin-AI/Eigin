@testable import Eigin
import Foundation
import Testing

@Suite("Markdown Truncation")
struct MarkdownTruncationTests {
    @Test func shortTextIsUntouched() {
        let result = MarkdownTruncation.truncate("short", limit: 100)
        #expect(!result.truncated)
        #expect(result.text == "short")
    }

    @Test func cutsAtParagraphBoundary() {
        let text = "First paragraph.\n\nSecond paragraph that keeps going " + String(
            repeating: "x",
            count: 200
        )
        let result = MarkdownTruncation.truncate(text, limit: 50)
        #expect(result.truncated)
        #expect(result.text == "First paragraph.")
    }

    @Test func fallsBackToLineBreak() {
        let text = String(repeating: "word ", count: 30) + "end"
        let result = MarkdownTruncation.truncate(text, limit: 10)
        #expect(result.truncated)
        #expect(!result.text.isEmpty)
        #expect(result.text.count <= 10)
    }

    @Test func fallsBackToWordBoundary() {
        let text = "aaaaaaaaaaaa bbbbbbbbbbbb c"
        let result = MarkdownTruncation.truncate(text, limit: 15)
        #expect(result.truncated)
        #expect(result.text == "aaaaaaaaaaaa")
    }

    @Test func noMidWordCutEver() {
        let text = (0 ..< 100).map { "word\($0)" }.joined(separator: " ")
        let result = MarkdownTruncation.truncate(text, limit: 97)
        #expect(!result.text.hasSuffix("word9"))
        #expect(result.text.count <= 97)
    }

    @Test func exactLimitIsNotTruncated() {
        let text = String(repeating: "a", count: 50)
        let result = MarkdownTruncation.truncate(text, limit: 50)
        #expect(!result.truncated)
        #expect(result.text == text)
    }
}
