@testable import Eigin
import Testing

@Suite("StreamThrottler.wholeWords")
@MainActor
struct StreamThrottlerTests {
    private func wholeWords(_ text: String) -> String? {
        StreamThrottler.wholeWords(text[...]).map(String.init)
    }

    @Test func trimsBackToLastCompletedWord() {
        #expect(wholeWords("hello wor") == "hello ")
    }

    @Test func keepsTextAlreadyEndingAtWhitespace() {
        #expect(wholeWords("hello ") == "hello ")
    }

    @Test func returnsNilWhenNoWordCompletedYet() {
        #expect(wholeWords("hello") == nil)
    }

    @Test func treatsNewlineAsWordBoundary() {
        #expect(wholeWords("line one\nlin") == "line one\n")
    }

    @Test func trimsToTheLastOfConsecutiveSpaces() {
        #expect(wholeWords("one two   thre") == "one two   ")
    }
}
