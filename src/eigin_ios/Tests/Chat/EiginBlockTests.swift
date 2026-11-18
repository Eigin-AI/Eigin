@testable import Eigin
import Testing

@Suite("Eigin content blocks")
struct EiginBlockTests {
    private let payload = #"{"type":"attribution","source":"apple-weather"}"#

    private func split(_ text: String, streaming: Bool = false) -> [ContentBlock] {
        ContentBlock.split(text, messageID: "message", isStreaming: streaming)
    }

    @Test func rendersAndDeduplicatesWithinMessage() {
        let marker = "```eigin\n\(payload)\n```"
        let blocks = split("Rain today.\n\n\(marker)\n\n\(marker)")
        #expect(blocks
            .count(where: { $0.kind == .eigin(.attribution(source: .appleWeather)) }) == 1)
        #expect(split(marker).count == 1)
        #expect(split(marker) == split(marker))
        #expect(blocks.first?.text.contains("Rain today") == true)
    }

    @Test func acceptsJSONWhitespaceAndOrder() {
        let blocks =
            split(
                "```eigin\n{\n  \"source\": \"apple-weather\",\n  \"type\": \"attribution\"\n}\n```"
            )
        #expect(blocks.first?.kind == .eigin(.attribution(source: .appleWeather)))
    }

    @Test(arguments: [
        #"{"type":"unknown","source":"apple-weather"}"#,
        #"{"type":"attribution","source":"unknown"}"#,
        #"{"type":"attribution","source":"apple-weather","url":"https://example.com"}"#,
        #"{"type":"attribution","source":1}"#,
        "not JSON",
    ]) func invalidBlocksStayCode(payload: String) {
        #expect(split("```eigin\n\(payload)\n```").first?.kind == .code)
    }

    @Test func holdsUntilClosedAndFallsBackWhenFinished() {
        for prefix in ["`", "``", "```", "```e", "```eigin", "```eigin\n", "```eigin\n\(payload)"] {
            #expect(split(prefix, streaming: true).isEmpty)
        }
        #expect(split("```eigin\n\(payload)").first?.kind == .code)
        #expect(split("```eigin").first?.kind == .code)
        #expect(split("```eigin\n\(payload)\n```", streaming: true).first?
            .kind == .eigin(.attribution(source: .appleWeather)))
    }

    @Test func examplesInsideLongerFencesStayLiteral() {
        let text = "````markdown\n```eigin\n\(payload)\n```\n````\nAfter"
        let blocks = split(text)
        #expect(blocks.count == 2)
        #expect(blocks.first?.kind == .code)
        #expect(blocks.first?.text.contains("```eigin") == true)
        #expect(blocks.last?.text == "After")
    }

    @Test func ordinaryFencesAndNearMissesStayCode() {
        for language in ["json", "swift", "eigin-ui", "Eigin"] {
            #expect(split("```\(language)\n\(payload)\n```").first?.kind == .code)
        }
    }
}
