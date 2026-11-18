import EiginSDK
import Testing

private typealias Agent = EiginSDK.Experimental.Agent

@Suite("Experimental agent checkpoint bindings")
struct AgentCheckpointTests {
    @Test func interruptedBatchPreservesMetadataAndCompletedResults() throws {
        let round = Agent.Round()
        try round.acceptEvent(event: .contentDelta(text: "Working"))
        try round.acceptEvent(event: .providerMetadata(values: ["signature": "opaque"]))
        for id in ["a", "b"] {
            try round.acceptEvent(event: .toolCall(call: .init(id: id, kind: "function", name: "action", arguments: "{}")))
        }
        try round.acceptEvent(event: .finished(reason: .toolCalls))
        guard case let .tools(assistant, _) = try round.finishStream() else {
            Issue.record("Expected batch")
            return
        }
        let result = try round.recordResult(result: .init(toolCallId: "a", content: "Completed"))
        let progress = Agent.Progress(
            retainedCount: 2, isDone: false, isExecutingTools: true,
            partialContent: "Working", currentMessageIndex: 0
        )
        let checkpoint = Agent.checkpoint([assistant, result], progress: progress)
        #expect(checkpoint == Agent.checkpoint([assistant, result], progress: progress))
        #expect(checkpoint.count == 3)
        #expect(checkpoint[0].origin == .produced(index: 0))
        #expect(checkpoint[0].message == assistant)
        #expect(checkpoint[1].message == result)
        #expect(checkpoint[2].origin == .interruptedTool)
        #expect(checkpoint[2].message.toolCallId == "b")
        #expect(checkpoint[2].message.content == "Tool execution was interrupted. Completion is unknown; do not repeat the action without checking its state.")
    }

    @Test func partialProseAndCompletedOutput() {
        let progress = Agent.Progress(
            retainedCount: 0, isDone: false, isExecutingTools: false,
            partialContent: "Partial", currentMessageIndex: nil
        )
        let partial = Agent.checkpoint([], progress: progress)
        #expect(partial.count == 1)
        #expect(partial[0].origin == .partialProse)
        #expect(partial[0].message.content == "Partial")
        #expect(partial[0].message.toolCalls == nil)
        let done = Agent.checkpoint(partial.map(\.message), progress: .init(
            retainedCount: 0, isDone: true, isExecutingTools: false,
            partialContent: "Partial", currentMessageIndex: 0
        ))
        #expect(done.count == 1)
        #expect(done[0].origin == .produced(index: 0))
        #expect(done[0].message == partial[0].message)
        let committed = Agent.checkpoint(partial.map(\.message), progress: .init(
            retainedCount: 1, isDone: false, isExecutingTools: false,
            partialContent: "Partial", currentMessageIndex: 0
        ))
        #expect(committed == done)
    }
}
