import EiginSDK
import Foundation
import Testing

private typealias Agent = EiginSDK.Experimental.Agent

@Suite("Experimental agent round bindings")
struct AgentRoundTests {
    @Test func orderedEventsAndSequentialResults() throws {
        let round = Agent.Round()
        try round.acceptEvent(event: .contentDelta(text: "Before "))
        try round.acceptEvent(event: .contentDelta(text: "tools"))
        for id in ["a", "b"] {
            try round.acceptEvent(event: .toolCall(call: .init(id: id, kind: "function", name: "lookup", arguments: "{}")))
        }
        try round.acceptEvent(event: .providerMetadata(values: ["signature": "opaque"]))
        try round.acceptEvent(event: .finished(reason: .toolCalls))
        #expect(round.hasFinished())
        guard case let .tools(message, calls) = try round.finishStream() else {
            Issue.record("Expected executable calls")
            return
        }
        #expect(message.content == "Before tools")
        #expect(message.providerMetadata == ["signature": "opaque"])
        #expect(calls.map(\.id) == ["a", "b"])
        for id in ["a", "b"] {
            let result = try round.recordResult(result: .init(toolCallId: id, content: "result-\(id)"))
            #expect(result.toolCallId == id)
            #expect(result.content == "result-\(id)")
            #expect(result.name == "lookup")
        }
    }

    @Test func inlineExchangeLeavesProseForFinalReply() throws {
        let round = Agent.Round()
        try round.acceptEvent(event: .contentDelta(text: "before"))
        let exchange = try round.recordInlineExchange(
            call: .init(id: "inline", kind: "function", name: "lookup", arguments: "{}"),
            result: .init(toolCallId: "inline", content: "result")
        )
        #expect(exchange.map(\.role) == ["assistant", "tool"])
        #expect(exchange[0].content == nil)
        #expect(round.partialContent() == "before")
        try round.acceptEvent(event: .contentDelta(text: " after"))
        try round.acceptEvent(event: .finished(reason: .stop))
        guard case let .reply(message) = try round.finishStream() else {
            Issue.record("Expected reply")
            return
        }
        #expect(message.content == "before after")
    }

    @Test(arguments: [
        "{}", "\u{FEFF}{}", "{\"a\":1,}", "{\"a\":[1,]}", "{,}", "{\"a\":1,,}",
        "{\"a\":,}", "{\"n\":1e999}", "[]", "null", "{} false",
        String(repeating: "{\"a\":", count: 512) + "0" + String(repeating: "}", count: 512),
        String(repeating: "{\"a\":", count: 513) + "0" + String(repeating: "}", count: 513),
    ])
    @MainActor func argumentAcceptanceMatchesHostParser(_ arguments: String) throws {
        let expected = (try? JSONSerialization.jsonObject(with: Data(arguments.utf8))) is [String: Any]
        let round = Agent.Round()
        try round.acceptEvent(event: .toolCall(call: .init(id: "a", kind: "function", name: "lookup", arguments: arguments)))
        try round.acceptEvent(event: .finished(reason: .toolCalls))
        if expected {
            guard case let .tools(_, calls) = try round.finishStream() else {
                Issue.record("Expected valid calls")
                return
            }
            #expect(calls.first?.arguments == arguments)
        } else {
            #expect(throws: Agent.Failure.InvalidToolCall) { try round.finishStream() }
        }
    }

    @Test func deepArgumentsValidateOnHostWorkerThread() throws {
        let arguments = String(repeating: "{\"a\":", count: 512) + "0" + String(repeating: "}", count: 512)
        let round = Agent.Round()
        try round.acceptEvent(event: .toolCall(call: .init(id: "deep", kind: "function", name: "lookup", arguments: arguments)))
        try round.acceptEvent(event: .finished(reason: .toolCalls))
        guard case let .tools(_, calls) = try round.finishStream() else {
            Issue.record("Expected valid calls")
            return
        }
        #expect(calls.first?.arguments == arguments)
    }

    @Test func unfinishedHandlesAreIndependentAndErrorsAreTyped() throws {
        var unfinished: Agent.Round? = Agent.Round()
        try unfinished?.acceptEvent(event: .contentDelta(text: "discarded"))
        #expect(throws: Agent.Failure.Interrupted) {
            let value = try #require(unfinished)
            return try value.finishStream()
        }
        unfinished = nil
        let next = Agent.Round()
        #expect(next.partialContent().isEmpty)
        try next.acceptEvent(event: .finished(reason: .stop))
        #expect(try next.finishStream() == .empty)
    }
}
