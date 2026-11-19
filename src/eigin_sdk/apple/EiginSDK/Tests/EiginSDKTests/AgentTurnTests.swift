import EiginSDK
import Testing

private typealias Agent = EiginSDK.Experimental.Agent

@Suite("Experimental agent turn bindings")
struct AgentTurnTests {
    private var active: Agent.Signals {
        .init(cancelled: false, stopped: false, terminate: false)
    }

    @Test func toolsContinueAndRecoveryIsShared() throws {
        let turn = Agent.Turn()
        #expect(try turn.beginRound() == .requestInference)
        let round = Agent.Round()
        try round.acceptEvent(event: .toolCall(call: .init(
            id: "call", kind: "function", name: "lookup", arguments: "{}"
        )))
        try round.acceptEvent(event: .finished(reason: .toolCalls))
        let outcome = try round.finishStream()
        #expect(try turn.completeRound(outcome: outcome) == .executeTools)
        let result = try round.recordResult(result: .init(toolCallId: "call", content: "done"))
        #expect(result.content == "done")
        #expect(try turn.completeTools(terminate: false) == .continue)
        #expect(try turn.beginRound() == .requestInference)
        #expect(try turn.failRound(failure: .interruption, signals: active, allowInterruptionRecovery: true)
            == .recover(reason: .interrupted))
        #expect(try turn.beginRound() == .requestInference)
        #expect(try turn.completeRound(outcome: .empty) == .checkEmptyReply)
        #expect(try turn.resolveEmptyReply(signals: active) == .missingReply)
        #expect(turn.roundsExecuted() == 3)
        #expect(throws: Agent.TurnError.self) { try turn.beginRound() }
    }

    @Test func localInlineExchangeIsNotExecutedAgain() throws {
        let turn = Agent.Turn()
        #expect(try turn.beginRound() == .requestInference)
        let round = Agent.Round()
        let exchange = try round.recordInlineExchange(
            call: .init(id: "inline", kind: "function", name: "lookup", arguments: "{}"),
            result: .init(toolCallId: "inline", content: "done")
        )
        try round.acceptEvent(event: .finished(reason: .stop))
        #expect(try turn.completeRound(outcome: round.finishStream()) == .checkEmptyReply)
        #expect(try turn.resolveEmptyReply(signals: active)
            == .recover(reason: .missingReply))
        #expect(exchange.map(\.role) == ["assistant", "tool"])
        #expect(try turn.beginRound() == .requestInference)
        #expect(try turn.failRound(failure: .interruption, signals: active, allowInterruptionRecovery: false)
            == .propagateFailure)
    }

    @Test func replyAndRoundBudgetHaveDistinctFinishReasons() throws {
        let replyTurn = Agent.Turn()
        #expect(try replyTurn.beginRound() == .requestInference)
        let round = Agent.Round()
        try round.acceptEvent(event: .contentDelta(text: "Done"))
        try round.acceptEvent(event: .finished(reason: .stop))
        #expect(try replyTurn.completeRound(outcome: round.finishStream()) == .finish(reason: .reply))

        let turn = Agent.Turn()
        let tools = Agent.Round()
        try tools.acceptEvent(event: .toolCall(call: .init(id: "a", kind: "function", name: "lookup", arguments: "{}")))
        try tools.acceptEvent(event: .finished(reason: .toolCalls))
        let batch = try tools.finishStream()
        for _ in 0 ..< 40 {
            #expect(try turn.beginRound() == .requestInference)
            #expect(try turn.completeRound(outcome: batch) == .executeTools)
            #expect(try turn.completeTools(terminate: false) == .continue)
        }
        #expect(try turn.beginRound() == .finish(reason: .roundLimit))
    }

    @Test func lifecycleAndIndependentHandles() throws {
        let turn = Agent.Turn()
        #expect(throws: Agent.TurnError.self) { try turn.completeTools(terminate: false) }
        #expect(try turn.beginRound() == .requestInference)
        #expect(throws: Agent.TurnError.self) { try turn.beginRound() }
        let cancelled = Agent.Signals(cancelled: true, stopped: false, terminate: false)
        #expect(try turn.completeRound(outcome: .empty) == .checkEmptyReply)
        #expect(try turn.resolveEmptyReply(signals: cancelled) == .cancelled)
        let second = Agent.Turn()
        #expect(second.roundsExecuted() == 0)
        #expect(try second.beginRound() == .requestInference)
        #expect(try second.completeRound(outcome: .empty) == .checkEmptyReply)
        #expect(try second.resolveEmptyReply(signals: .init(cancelled: false, stopped: false, terminate: true)) == .finish(reason: .explicitTermination))
    }
}
