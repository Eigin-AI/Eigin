import EiginSDK
import Synchronization
import Testing

private typealias Agent = EiginSDK.Experimental.Agent
private typealias Inference = EiginSDK.Experimental.Inference

@Suite("Complete turn callback ordering")
struct ChatTurnOrderingTests {
    @Test func presentationAndResultAdmissionStayOrdered() async throws {
        let trace = Mutex<[String]>([])
        let requests = Mutex(0)
        let operation = Mutex<Agent.ChatTurn?>(nil)
        let turn = makeTurn(input: turnInput(), router: .init(), services: .init(
            prepare: { _, _ in
                let index = requests.withLock { value in value += 1; return value }
                trace.withLock { $0.append("prepare") }
                return turnRequest(index == 1 ? [
                    .contentDelta(text: "Checking"), .toolCall(call: turnCall("a")), .finished(reason: .toolCalls),
                ] : [.contentDelta(text: "Done"), .finished(reason: .stop)])
            }, notify: { event in
                switch event {
                case let .output(entries):
                    trace.withLock { $0.append(entries.last?.message.role == "tool" ? "result admitted" : "batch admitted") }
                case .finished:
                    trace.withLock { $0.append("finished") }
                default: break
                }
            }, present: { work in
                switch work {
                case .finishToolProse:
                    trace.withLock { $0.append("finish tool prose") }
                case .beforeTool:
                    trace.withLock { $0.append("before tool") }
                    let checkpoint = operation.withLock { $0 }?.checkpoint()
                    #expect(checkpoint?.map(\.message.role) == ["assistant", "tool"])
                    #expect(checkpoint?.last?.message.content != "result")
                case .afterTool:
                    trace.withLock { $0.append("after tool") }
                    #expect(operation.withLock { $0 }?.checkpoint().last?.message.content != "result")
                case .drain:
                    trace.withLock { $0.append("drain") }
                }
            }, execute: { call in
                trace.withLock { $0.append("execute") }
                return .init(toolCallId: call.id, content: "result", isError: false)
            }, refreshTools: {
                trace.withLock { $0.append("refresh") }
                return nil
            }, completionRequested: {
                trace.withLock { $0.append("check completion") }
                return false
            }, classifyFailure: { _ in .terminal }
        ))
        operation.withLock { $0 = turn }
        defer { operation.withLock { $0 = nil } }
        let output = try await turn.run()
        #expect(output.map(\.message.role) == ["assistant", "tool", "assistant"])
        #expect(trace.withLock { $0 } == [
            "prepare", "finish tool prose", "batch admitted", "before tool", "execute", "after tool",
            "result admitted", "check completion", "refresh", "prepare", "drain", "finished",
        ])
    }

    @Test func streamMissingReplyChecksCompletionTwiceBeforeRecovery() async throws {
        let checks = Mutex(0)
        let requests = Mutex(0)
        let turn = makeTurn(input: turnInput(), router: .init(), services: .init(
            prepare: { _, _ in
                requests.withLock { $0 += 1 }
                let events = TurnEvents([.contentDelta(text: "Partial")])
                return .init(providerID: "provider", local: false, services: .init(validate: { _ in }, open: { _, _ in
                    .init(next: {
                        if let event = await events.next() { return event }
                        throw Inference.RequestFailure.MissingReply
                    }, cancel: {})
                }))
            }, notify: { _ in }, execute: { call in
                Issue.record("No tools expected")
                return .init(toolCallId: call.id, content: "", isError: true)
            }, refreshTools: { nil }, completionRequested: {
                let check = checks.withLock { value in value += 1; return value }
                return check == 2
            }, classifyFailure: { _ in .terminal }
        ))
        #expect(try await turn.run().isEmpty)
        #expect(checks.withLock { $0 } == 2)
        #expect(requests.withLock { $0 } == 1)
        #expect(turn.checkpoint().last?.message.content == "Partial")
    }
}
