@testable import EiginSDK
import Synchronization
import Testing

private typealias Agent = EiginSDK.Experimental.Agent
private typealias Inference = EiginSDK.Experimental.Inference

@Suite("Turn tool scheduling")
struct ChatTurnSchedulingTests {
    @Test(arguments: [false, true])
    func stopBeforeToolExecutionResolvesInlineConsumerWithoutExecutingTool(taskStarted: Bool) async throws {
        let beforeExecution = TurnGate()
        let pending = Mutex<(@Sendable () -> Void)?>(nil)
        let result = Mutex<Inference.LocalToolResult?>(nil)
        let executions = Mutex(0)
        let host = TurnHostFixture(prepare: { _, inline in
            .init(providerID: "local", local: true, services: .init(validate: { _ in }, open: { _, _ in
                let value = await inline.execute(turnCall("queued"))
                result.withLock { $0 = value }
                return .init(next: { nil }, cancel: {})
            }))
        }, execute: { call in
            executions.withLock { $0 += 1 }
            return .init(toolCallId: call.id, content: "executed", isError: false)
        }, refreshTools: { nil }, classifyFailure: { _ in .terminal })
        let turn = Agent.ChatTurn(input: turnInput(), router: .init(), host: host, scheduleTool: { launch in
            if taskStarted { launch() } else { pending.withLock { $0 = launch } }
        }, beforeToolExecution: {
            if taskStarted { await beforeExecution.wait() }
        })
        let task = Task { try await turn.run() }
        if taskStarted {
            try await waitForTurn { await beforeExecution.waiting }
        } else {
            try await waitForTurn { pending.withLock { $0 != nil } }
        }
        #expect(turn.stop().isEmpty)
        #expect(try await task.value.isEmpty)
        if taskStarted {
            await beforeExecution.release()
        } else {
            let launch = try #require(pending.withLock { $0 })
            launch()
        }
        try await waitForTurn { result.withLock { $0 != nil } }
        #expect(result.withLock { $0?.toolCallId } == "queued")
        #expect(result.withLock { $0?.isError } == true)
        #expect(executions.withLock { $0 } == 0)
        #expect(turn.checkpoint().isEmpty)
    }
}
