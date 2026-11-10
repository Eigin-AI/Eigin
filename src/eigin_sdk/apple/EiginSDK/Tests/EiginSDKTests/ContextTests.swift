import EiginSDK
import Foundation
import Testing

private typealias Context = EiginSDK.Experimental.Context

@Suite("Experimental context bindings")
struct ContextTests {
    @Test func unicodeEstimationMatchesSwiftCharacters() {
        for grapheme in ["x", "e\u{301}", "👨‍👩‍👧‍👦", "🇩🇰", "👍🏽", "\r\n", "क्‍ष"] {
            for count in [0, 3, 4, 12, 49, 50] {
                let text = String(repeating: grapheme, count: count)
                #expect(Context.estimate(text) == max(1, text.count / 4))
            }
        }
    }

    @Test func valuesCarryToolsNamesAndReasoning() {
        #expect(Context.estimate(messages: [.init(role: "user")]) == 5)
        #expect(Context.estimate(messages: [.init(role: "user", name: "")]) == 6)
        let message = Context.Message(
            role: "assistant", name: "name",
            toolCalls: [.init(name: "test", arguments: "{}")],
            additionalInputTokens: 17, hasReasoningHistory: true
        )
        #expect(Context.estimate(messages: [message]) == 35)
        #expect(Context.estimateRequest(messages: [message], toolCount: 2) == 335)
        #expect(Context.estimate(toolCount: 2) == 300)
        #expect(Context.truncateForBudget(messages: [message], tokenBudget: 30).startIndex == 1)
    }

    @Test func selectionsCarryIndicesOptionalsAndSignedBudgets() {
        let messages = [Context.Message(role: "user", content: String(repeating: "👨‍👩‍👧‍👦", count: 400))]
        let partial = Context.truncateForBudget(messages: messages, tokenBudget: 30)
        #expect(partial.startIndex == 0)
        #expect(partial.partialContent == "…" + String(repeating: "👨‍👩‍👧‍👦", count: 103))
        let empty = Context.truncateForBudget(messages: messages, tokenBudget: Int.min)
        #expect(empty.startIndex == 1)
        #expect(empty.partialContent == nil)
        #expect(Context.retainedTail(messages: messages, tokenBudget: -1).startIndex == 0)
        #expect(Context.windowedForBudget(messages: messages, highMark: -1, lowMark: -2)
            .startIndex == 0)
    }

    @Test func summaryResultsAndFoundationWhitespaceRoundTrip() throws {
        for scalar in [
            0x09,
            0x0A,
            0x0B,
            0x0C,
            0x0D,
            0x20,
            0x85,
            0xA0,
            0x1680,
            0x2000,
            0x200A,
            0x200B,
            0x2028,
            0x2029,
            0x202F,
            0x205F,
            0x3000,
            0x180E,
            0xFEFF,
        ] {
            let whitespace = try String(#require(UnicodeScalar(scalar)))
            let body = whitespace + String(repeating: "e\u{301}", count: 50) + whitespace
            let expected = body.trimmingCharacters(in: .whitespacesAndNewlines)
            #expect(Context.parseSummary("<conversation_summary>" + body) == .accepted(expected))
        }
        #expect(Context.parseSummary("  no tag  ") == .missingOpeningTag(trimmedLength: 6))
        #expect(Context
            .parseSummary("<conversation_summary>" + String(repeating: "👨‍👩‍👧‍👦", count: 49)) ==
            .tooShort(bodyLength: 49))
    }
}
