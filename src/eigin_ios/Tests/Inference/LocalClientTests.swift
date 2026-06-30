@testable import Eigin
import Foundation
import Testing

@Suite("LocalClient")
struct LocalClientTests {
    // MARK: - convertJSONArgsToGemma

    @Test func convertJSONArgsToGemmaSimple() {
        let json = "{\"name\":\"Alice\"}"
        let gemma = LocalClient.convertJSONArgsToGemma(json)
        #expect(gemma.contains("name:"))
        #expect(gemma.contains("<|\"|>Alice<|\"|>"))
    }

    @Test func convertJSONArgsToGemmaNested() {
        let json = "{\"a\":{\"b\":\"hello\"}}"
        let gemma = LocalClient.convertJSONArgsToGemma(json)
        #expect(gemma.contains("a:{"))
        #expect(gemma.contains("b:<|\"|>hello<|\"|>"))
    }

    @Test func convertJSONArgsToGemmaWithSpecialChars() {
        let json = "{\"msg\":\"hello\\\"world\"}"
        let gemma = LocalClient.convertJSONArgsToGemma(json)
        #expect(gemma.contains("<|\"|>"))
    }

    @Test func convertJSONArgsToGemmaInvalidJSON() {
        let invalid = "{not json}"
        let result = LocalClient.convertJSONArgsToGemma(invalid)
        #expect(result == invalid)
    }

    // MARK: - FC history wire format

    //
    // These pin the exact marker output of the Gemma function-calling history
    // encoders. The strings must match Gemma's chat template precisely or
    // replayed tool history corrupts, so the format is a sticky contract.

    @Test("renderGemmaToolCall wraps name + args in tool_call markers")
    func renderToolCall() {
        let rendered = LocalClient.renderGemmaToolCall(
            name: "web_search",
            jsonArgs: "{\"query\":\"weather\"}"
        )
        #expect(rendered == "<|tool_call>call:web_search{query:<|\"|>weather<|\"|>}<tool_call|>")
    }

    @Test("renderGemmaToolResponse converts a JSON-object body")
    func renderToolResponseJSON() {
        let rendered = LocalClient.renderGemmaToolResponse(
            name: "web_search",
            content: "{\"result\":\"ok\"}"
        )
        #expect(
            rendered
                == "<|tool_response>response:web_search{result:<|\"|>ok<|\"|>}<tool_response|>"
        )
    }

    @Test("renderGemmaToolResponse wraps plain text in a value field")
    func renderToolResponsePlainText() {
        let rendered = LocalClient.renderGemmaToolResponse(
            name: "web_fetch",
            content: "hello world"
        )
        #expect(
            rendered
                == "<|tool_response>response:web_fetch{value:<|\"|>hello world<|\"|>}<tool_response|>"
        )
    }
}
