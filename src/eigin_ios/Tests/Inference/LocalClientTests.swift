@testable import Eigin
import Foundation
import Testing

@Suite("LocalClient")
struct LocalClientTests {
    // MARK: - parseToolCalls

    @Test func parseToolCallsEmpty() {
        let result = LocalClient.parseToolCalls("Hello world")
        #expect(result.isEmpty)
    }

    @Test func parseToolCallsSingleCall() {
        let output = "<|tool_call>call:get_weather{\"location\":\"San Francisco\"}<tool_call|>"
        let calls = LocalClient.parseToolCalls(output)
        #expect(calls.count == 1)
        #expect(calls[0].function.name == "get_weather")
        #expect(calls[0].function.arguments == "{\"location\":\"San Francisco\"}")
    }

    @Test func parseToolCallsMultipleCalls() {
        let output = """
        Hello there<|tool_call>call:get_weather{\"location\":\"NYC\"}<tool_call|>
        <|tool_call>call:search{\"query\":\"news\"}<tool_call|>
        """
        let calls = LocalClient.parseToolCalls(output)
        #expect(calls.count == 2)
        #expect(calls[0].function.name == "get_weather")
        #expect(calls[0].function.arguments == "{\"location\":\"NYC\"}")
        #expect(calls[1].function.name == "search")
        #expect(calls[1].function.arguments == "{\"query\":\"news\"}")
    }

    @Test func parseToolCallsNoArgs() {
        let output = "<|tool_call>call:ping{}<tool_call|>"
        let calls = LocalClient.parseToolCalls(output)
        #expect(calls.count == 1)
        #expect(calls[0].function.name == "ping")
        #expect(calls[0].function.arguments == "{}")
    }

    @Test func parseToolCallsGemmaStyleUnquotedKeys() {
        let output = "<|tool_call>call:get_weather{location:<|\"|>San Francisco<|\"|>}<tool_call|>"
        let calls = LocalClient.parseToolCalls(output)
        #expect(calls.count == 1)
        #expect(calls[0].function.name == "get_weather")
        #expect(calls[0].function.arguments.contains("\"location\":"))
        #expect(calls[0].function.arguments.contains("San Francisco"))
    }

    // MARK: - convertGemmaArgsToJSON

    @Test func convertGemmaArgsToJSONAlreadyValid() {
        let gemma = "{\"name\":\"John\"}"
        let json = LocalClient.convertGemmaArgsToJSON(gemma)
        #expect(json == "{\"name\":\"John\"}")
    }

    @Test func convertGemmaArgsToJSONUnquotedKeys() {
        let gemma = "{name:<|\"|>John<|\"|>}"
        let json = LocalClient.convertGemmaArgsToJSON(gemma)
        #expect(json.contains("\"name\":"))
        #expect(json.contains("John"))
    }

    @Test func convertGemmaArgsToJSONReplacesGemmaQuotes() {
        let gemma = "{msg:<|\"|>hello<|\"|>}"
        let json = LocalClient.convertGemmaArgsToJSON(gemma)
        #expect(json.contains("\"msg\":"))
        #expect(json.contains("hello"))
        #expect(!json.contains("<|\"|>"))
    }

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
}
