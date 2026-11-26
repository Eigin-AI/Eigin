import EiginSDK
import Foundation
import Synchronization
import Testing

private typealias Inference = EiginSDK.Experimental.Inference
private typealias Agent = EiginSDK.Experimental.Agent

@Suite("Complete turn cancellation")
struct ChatTurnCancellationTests {
    @Test(arguments: ["prepare", "notify", "present", "execute", "refresh", "signals"], [false, true])
    func stopAndTaskCancellationReachSuspendedCapabilities(phase: String, cancelTask: Bool) async throws {
        let entered = Mutex(false)
        let cancelled = Mutex(false)
        let wait: @Sendable () async -> Void = {
            entered.withLock { $0 = true }
            do { try await Task.sleep(for: .seconds(60)) }
            catch is CancellationError { cancelled.withLock { $0 = true } }
            catch { Issue.record("Unexpected wait error: \(error)") }
        }
        let turn = makeTurn(input: turnInput(), router: .init(), services: .init(
            prepare: { _, _ in
                if phase == "prepare" { await wait() }
                return turnRequest([.toolCall(call: turnCall("call")), .finished(reason: .toolCalls)])
            }, notify: { _ in
                if phase == "notify" { await wait() }
            }, present: { _ in
                if phase == "present" { await wait() }
            }, execute: { call in
                if phase == "execute" { await wait() }
                return .init(toolCallId: call.id, content: "result", isError: false)
            }, refreshTools: {
                if phase == "refresh" { await wait() }
                return nil
            }, completionRequested: {
                if phase == "signals" { await wait() }
                return false
            }, classifyFailure: { _ in .terminal }
        ))
        let task = Task { try await turn.run() }
        try await waitForTurn { entered.withLock { $0 } }
        let checkpoint: [Agent.OutputEntry]
        if cancelTask {
            checkpoint = turn.checkpoint()
            task.cancel()
            do { _ = try await task.value; Issue.record("Expected cancellation") }
            catch is CancellationError {}
        } else {
            checkpoint = turn.stop()
            #expect(try await task.value.isEmpty)
        }
        try await waitForTurn { cancelled.withLock { $0 } }
        #expect(turn.checkpoint() == checkpoint)
    }

    @Test func latePreparationCannotStartARequestAfterStop() async throws {
        let gate = TurnGate()
        let returned = Mutex(false)
        let opened = Mutex(false)
        let turn = makeTurn(input: turnInput(), router: .init(), services: .init(
            prepare: { _, _ in
                await gate.wait()
                defer { returned.withLock { $0 = true } }
                return .init(providerID: "provider", local: true, services: .init(validate: { _ in }, open: { _, _ in
                    opened.withLock { $0 = true }
                    return .init(next: { nil }, cancel: {})
                }))
            }, notify: { _ in }, execute: { call in
                .init(toolCallId: call.id, content: "", isError: false)
            }, refreshTools: { nil }, classifyFailure: { _ in .terminal }
        ))
        let task = Task { try await turn.run() }
        try await waitForTurn { await gate.waiting }
        #expect(turn.stop().isEmpty)
        #expect(try await task.value.isEmpty)
        await gate.release()
        try await waitForTurn { returned.withLock { $0 } }
        #expect(!opened.withLock { $0 })
    }

    @Test func lateInlineResultCannotChangeStoppedTurn() async throws {
        let gate = TurnGate()
        let returned = Mutex(false)
        let nativeResult = Mutex<Inference.LocalToolResult?>(nil)
        let closed = Mutex(false)
        let calls = Mutex(0)
        let saved = Mutex<Agent.InlineTools?>(nil)
        let turn = makeTurn(input: turnInput(), router: .init(), services: .init(
            prepare: { _, inline in
                saved.withLock { $0 = inline }
                return .init(providerID: "local", local: true, services: .init(validate: { _ in }, open: { _, _ in
                    let result = await inline.execute(turnCall("late"))
                    nativeResult.withLock { $0 = result }
                    return .init(next: { nil }, cancel: { closed.withLock { $0 = true } })
                }))
            }, notify: { _ in }, execute: { call in
                calls.withLock { $0 += 1 }
                await gate.wait()
                returned.withLock { $0 = true }
                return .init(toolCallId: call.id, content: "completed", isError: false)
            }, refreshTools: { nil }, classifyFailure: { _ in .terminal }
        ))
        let task = Task { try await turn.run() }
        try await waitForTurn { await gate.waiting }
        #expect(turn.stop().isEmpty)
        #expect(try await task.value.isEmpty)
        #expect(nativeResult.withLock { $0 } == nil)
        await gate.release()
        try await waitForTurn { returned.withLock { $0 } && closed.withLock { $0 } }
        #expect(nativeResult.withLock { $0?.content } == "completed")
        #expect(nativeResult.withLock { $0?.isError } == false)
        let inline = try #require(saved.withLock { $0 })
        #expect(await inline.execute(turnCall("stale")).isError)
        #expect(calls.withLock { $0 } == 1)
        #expect(turn.checkpoint().isEmpty)
    }

    @Test(arguments: [false, true])
    func overlappingRunDoesNotCancelFirstTurn(cancelledCaller: Bool) async throws {
        let gate = TurnGate()
        let turn = makeTurn(input: turnInput(), router: .init(), services: .init(
            prepare: { _, _ in
                await gate.wait()
                return turnRequest([.contentDelta(text: "answer"), .finished(reason: .stop)])
            }, notify: { _ in }, execute: { call in
                .init(toolCallId: call.id, content: "", isError: false)
            }, refreshTools: { nil }, classifyFailure: { _ in .terminal }
        ))
        let first = Task { try await turn.run() }
        try await waitForTurn { await gate.waiting }
        let secondGate = TurnGate()
        let second = Task {
            await secondGate.wait()
            return try await turn.run()
        }
        try await waitForTurn { await secondGate.waiting }
        if cancelledCaller { second.cancel() }
        await secondGate.release()
        do { _ = try await second.value; Issue.record("Expected one-shot rejection") }
        catch Agent.ChatFailure.AlreadyStarted {}
        await gate.release()
        #expect(try await first.value.last?.message.content == "answer")
    }
}
