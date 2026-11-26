import EiginSDK
import Synchronization
import Testing

private typealias Agent = EiginSDK.Experimental.Agent

@Suite("Complete turn callback cancellation")
struct ChatTurnLifecycleTests {
    @Test func cancellationInsideCompletionCheckPrecedesEmptyReplyRecovery() async throws {
        let turn = makeTurn(input: turnInput(), router: .init(), services: .init(
            prepare: { _, _ in turnRequest([.contentDelta(text: " "), .finished(reason: .stop)]) },
            execute: { call in .init(toolCallId: call.id, content: "", isError: false) },
            refreshTools: { nil }, completionRequested: {
                withUnsafeCurrentTask { $0?.cancel() }
                return false
            }, classifyFailure: { _ in .terminal }
        ))
        await #expect(throws: CancellationError.self) { try await turn.run() }
        #expect(turn.roundsExecuted == 1)
    }

    @Test(arguments: [false, true])
    func toolHookCancellationPreservesResultAdmission(after: Bool) async throws {
        let executions = Mutex(0)
        let preparations = Mutex(0)
        let turn = makeTurn(input: turnInput(), router: .init(), services: .init(
            prepare: { _, _ in
                preparations.withLock { $0 += 1 }
                return turnRequest([.toolCall(call: turnCall("a")), .finished(reason: .toolCalls)])
            }, present: { work in
                switch work {
                case .beforeTool where !after, .afterTool where after:
                    withUnsafeCurrentTask { $0?.cancel() }
                default: break
                }
            }, execute: { call in
                executions.withLock { $0 += 1 }
                return .init(toolCallId: call.id, content: "executed", isError: false)
            }, refreshTools: { nil }, classifyFailure: { _ in .terminal }
        ))
        await #expect(throws: CancellationError.self) { try await turn.run() }
        #expect(turn.roundsExecuted == (after ? 2 : 1))
        #expect(executions.withLock { $0 } == (after ? 1 : 0))
        #expect(preparations.withLock { $0 } == 1)
        #expect(turn.checkpoint().map(\.message.role) == ["assistant", "tool"])
        #expect((turn.checkpoint().last?.message.content == "executed") == after)
    }

    @Test(arguments: [false, true], [false, true])
    func streamCancellationPreservesPartialCheckpoint(propagate: Bool, cancelTask: Bool) async throws {
        var input = turnInput()
        input.propagateStreamCancellation = propagate
        let gate = TurnGate()
        let turn = makeTurn(input: input, router: .init(), services: .init(
            prepare: { _, _ in
                let events = TurnEvents([.contentDelta(text: "partial")])
                return .init(providerID: "provider", local: false, services: .init(validate: { _ in }, open: { _, _ in
                    .init(next: {
                        if let event = await events.next() { return event }
                        if cancelTask { await gate.wait() }
                        throw CancellationError()
                    }, cancel: {})
                }))
            }, execute: { call in .init(toolCallId: call.id, content: "", isError: false) },
            refreshTools: { nil }, classifyFailure: { _ in .terminal }
        ))
        let run = Task { try await turn.run() }
        if cancelTask {
            try await waitForTurn { await gate.waiting }
            run.cancel()
        }
        if propagate { await #expect(throws: CancellationError.self) { try await run.value } }
        else { #expect(try await run.value.isEmpty) }
        #expect(turn.checkpoint().last?.message.content == "partial")
        await gate.release()
    }
}
