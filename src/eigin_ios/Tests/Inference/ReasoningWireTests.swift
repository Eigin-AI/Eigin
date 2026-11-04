@testable import Eigin
import Foundation
import Testing

@Suite("Reasoning wire format", .serialized)
struct ReasoningWireTests {
    @Test func effortReachesHTTPAndNilOmitsIt() async throws {
        let url = "https://reasoning-wire.test/v1/chat/completions"
        let client: any LLMClient = OpenAICompatibleClient(
            baseURL: "https://reasoning-wire.test/v1", apiToken: "test",
            session: FakeURLProtocol.fakeSession()
        )
        for effort: ReasoningEffort? in [nil, .low, .high, ReasoningEffort.none] {
            FakeURLProtocol.stubResponse(
                for: url,
                data: Data("data: [DONE]\n\n".utf8),
                statusCode: 200
            )
            let stream = try await client.chatCompletionEventStream(
                messages: [ChatMessage(role: "user", content: "Hello")],
                model: "mistral-large-4-0", tools: nil, cacheKey: nil, reasoningEffort: effort
            )
            for try await _ in stream {}
            let data = try #require(FakeURLProtocol.lastRequestBody(for: url))
            let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(body["reasoning_effort"] as? String == effort?.rawValue)
        }
    }

    @Test func mixedMistralStreamPreservesAnswerAndTools() async throws {
        let url = "https://reasoning-stream.test/v1/chat/completions"
        let sse = [
            #"data: {"choices":[{"delta":{"content":[{"type":"thinking","thinking":[{"type":"text","text":"private trace"}]}]}}]}"#,
            "",
            #"data: {"choices":[{"delta":{"content":[{"type":"thinking","thinking":[]},{"type":"text","text":"Answer"}],"tool_calls":[{"index":0,"id":"call1","type":"function","function":{"name":"lookup","arguments":"{}"}}]}}]}"#,
            "",
            #"data: {"choices":[{"delta":{"content":" continues"}}]}"#,
            "",
            #"data: {"choices":[{"delta":{"content":null},"finish_reason":"tool_calls"}]}"#,
            "", "data: [DONE]", "",
        ].joined(separator: "\n")
        FakeURLProtocol.stubResponse(for: url, data: Data(sse.utf8), statusCode: 200)
        let client = OpenAICompatibleClient(
            baseURL: "https://reasoning-stream.test/v1", apiToken: "test",
            session: FakeURLProtocol.fakeSession()
        )
        let stream = try await client.chatCompletionEventStream(
            messages: [], model: "mistral-large-4-0", tools: nil, cacheKey: nil,
            reasoningEffort: .high
        )
        var text = ""
        var calledTool = false
        for try await event in stream {
            if case .contentDelta(let delta) = event { text += delta }
            if case .toolCall = event { calledTool = true }
        }
        #expect(text == "Answer continues")
        #expect(calledTool)
    }
}
