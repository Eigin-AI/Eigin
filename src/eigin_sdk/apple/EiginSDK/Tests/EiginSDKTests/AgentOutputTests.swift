import EiginSDK
import Testing

private typealias Agent = EiginSDK.Experimental.Agent

@Suite("Experimental turn output bindings")
struct AgentOutputTests {
    @Test func finishedOutputRejectsNewDraftWithoutChangingSnapshots() throws {
        let output = Agent.Output()
        _ = try output.beginDraft()
        try output.updateDraft(content: "Answer")
        let reply = try #require(output.checkpoint().first?.message)
        try output.finish(message: reply)
        let recorded = output.output()
        let retained = output.retainedOutput()
        let checkpoint = output.checkpoint()
        #expect(throws: Agent.Failure.InvalidPhase) { try output.beginDraft() }
        #expect(throws: Agent.Failure.InvalidPhase) { try output.updateDraft(content: "Replacement") }
        #expect(throws: Agent.Failure.InvalidPhase) { try output.beginTools() }
        #expect(throws: Agent.Failure.InvalidPhase) { try output.retainInterruptedProse() }
        #expect(output.output() == recorded)
        #expect(output.retainedOutput() == retained)
        #expect(output.checkpoint() == checkpoint)
    }

    @Test func stoppedBatchUsesOwnedProgress() throws {
        let output = Agent.Output()
        let draft = try output.beginDraft()
        let round = Agent.Round()
        try round.acceptEvent(event: .contentDelta(text: "Working"))
        try round.acceptEvent(event: .providerMetadata(values: ["signature": "opaque"]))
        for id in ["a", "b"] {
            try round.acceptEvent(event: .toolCall(call: .init(id: id, kind: "function", name: "action", arguments: "{}")))
        }
        try output.updateDraft(content: round.partialContent())
        try round.acceptEvent(event: .finished(reason: .toolCalls))
        guard case let .tools(assistant, _) = try round.finishStream() else {
            Issue.record("Expected batch")
            return
        }
        try output.beginTools()
        let batch = try output.recordBatch(message: assistant)
        #expect(batch.origin == .recorded(id: draft))
        let result = try round.recordResult(result: .init(toolCallId: "a", content: "Completed"))
        _ = try output.recordResult(message: result)
        let checkpoint = output.checkpoint()
        #expect(checkpoint == output.checkpoint())
        #expect(checkpoint.count == 3)
        #expect(checkpoint[0].message.providerMetadata == ["signature": "opaque"])
        #expect(checkpoint[1].message == result)
        #expect(checkpoint[2].message.toolCallId == "b")
        #expect(output.output().count == 2)
    }

    @Test func inlineExchangesAndRecoveryPreserveDraftProvenance() throws {
        let output = Agent.Output()
        let draft = try output.beginDraft()
        let round = Agent.Round()
        try round.acceptEvent(event: .contentDelta(text: "Partial"))
        try output.updateDraft(content: round.partialContent())
        for id in ["a", "b"] {
            let exchange = try round.recordInlineExchange(
                call: .init(id: id, kind: "function", name: "action", arguments: "{}"),
                result: .init(toolCallId: id, content: "Completed")
            )
            _ = try output.recordInlineExchange(messages: exchange)
        }
        let checkpoint = output.checkpoint()
        #expect(checkpoint.count == 5)
        #expect(checkpoint.last?.origin == .recorded(id: draft))
        _ = try output.retainInterruptedProse()
        #expect(try output.retainInterruptedProse() == nil)
        #expect(output.checkpoint() == checkpoint)
        let next = try output.beginDraft()
        #expect(next != draft)
        try output.updateDraft(content: "Recovered")
        let final = try #require(output.checkpoint().last)
        try output.finish(message: final.message)
        #expect(output.checkpoint().last == final)
        #expect(output.output().count == 6)
        #expect(output.retainedOutput().count == 5)
    }
}
