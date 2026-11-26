import EiginSDK
import Foundation
import Synchronization
import Testing

private typealias Agent = EiginSDK.Experimental.Agent
private typealias Inference = EiginSDK.Experimental.Inference

@Suite("SDK complete chat turns")
struct ChatTurnTests {
    @Test func headlessHostNeedsNoPresentationOrLifecycleWiring() async throws {
        let turn = Agent.ChatTurn(input: turnInput(), router: .init(), host: HeadlessHost())
        let output = try await turn.run()
        #expect(output.map(\.message.role) == ["assistant", "tool", "assistant"])
        #expect(output.last?.message.content == "answer")
    }

    @Test func cloudToolsContinueWithoutHostContinuationCommands() async throws {
        let contexts = Mutex([Agent.ChatContext]())
        let calls = Mutex([String]())
        let refreshes = Mutex(0)
        let turn = makeTurn(input: turnInput(), router: .init(), services: .init(
            prepare: { context, _ in
                let first = contexts.withLock { contexts in
                    contexts.append(context)
                    return contexts.count == 1
                }
                return turnRequest(first ? [
                    .toolCall(call: turnCall("a")), .toolCall(call: turnCall("b")), .finished(reason: .toolCalls),
                ] : [.contentDelta(text: "answer"), .finished(reason: .stop)])
            }, notify: { _ in }, execute: { call in
                calls.withLock { $0.append(call.id) }
                return .init(toolCallId: call.id, content: "result", isError: false)
            }, refreshTools: {
                refreshes.withLock { $0 += 1 }
                return [.init(name: "refreshed", description: "", parametersJson: "{}")]
            }, classifyFailure: { _ in .terminal }
        ))
        let output = try await turn.run()
        #expect(output.map(\.message.role) == ["assistant", "tool", "tool", "assistant"])
        #expect(output.last?.message.content == "answer")
        #expect(calls.withLock { $0 } == ["a", "b"])
        let prepared = contexts.withLock { $0 }
        #expect(prepared.count == 2)
        #expect(prepared[1].output.count == 3)
        #expect(prepared[1].tools?.first?.name == "refreshed")
        #expect(refreshes.withLock { $0 } == 1)
        #expect(turn.roundsExecuted == 2)
        #expect(turn.retainedOutput().count == 3)
        #expect(turn.checkpoint() == output)
    }

    @Test func localInlineExecutionResumesTheSameRequest() async throws {
        let calls = Mutex([String]())
        let prepared = Mutex(0)
        let saved = Mutex<Agent.InlineTools?>(nil)
        let turn = makeTurn(input: turnInput(), router: .init(), services: .init(
            prepare: { _, inline in
                saved.withLock { $0 = inline }
                prepared.withLock { $0 += 1 }
                let events = TurnEvents([.contentDelta(text: "answer"), .finished(reason: .stop)])
                return .init(providerID: "local", local: true, services: .init(validate: { _ in }, open: { _, _ in
                    let result = await inline.execute(turnCall("inline"))
                    #expect(result.content == "native result")
                    return .init(next: { await events.next() }, cancel: {})
                }))
            }, notify: { _ in }, execute: { call in
                calls.withLock { $0.append(call.id) }
                return .init(toolCallId: call.id, content: "native result", isError: false)
            }, refreshTools: { Issue.record("Inline tools must not refresh the registry"); return nil },
            classifyFailure: { _ in .terminal }
        ))
        let output = try await turn.run()
        #expect(output.map(\.message.role) == ["assistant", "tool", "assistant"])
        #expect(calls.withLock { $0 } == ["inline"])
        #expect(prepared.withLock { $0 } == 1)
        let inline = try #require(saved.withLock { $0 })
        #expect(await inline.execute(turnCall("stale")).isError)
        #expect(turn.checkpoint() == output)
        #expect(calls.withLock { $0 } == ["inline"])
    }

    @Test func hostErrorsRemainTypedAcrossTurnPreparation() async throws {
        let expected = Inference.RequestFailure.Host(id: "original", message: "original failure", failure: .notTheModelsFault)
        let turn = makeTurn(input: turnInput(), router: .init(), services: .init(
            prepare: { _, _ in throw expected }, notify: { _ in }, execute: { call in
                .init(toolCallId: call.id, content: "", isError: false)
            }, refreshTools: { nil }, classifyFailure: { _ in .terminal }
        ))
        do { _ = try await turn.run(); Issue.record("Expected host error") }
        catch let error as Inference.RequestFailure { #expect(error == expected) }
    }
}

private struct HeadlessHost: Agent.TurnHost {
    func prepare(_ context: Agent.ChatContext, inline _: Agent.InlineTools) async throws -> Agent.PreparedRequest {
        turnRequest(context.output.isEmpty
            ? [.toolCall(call: turnCall("a")), .finished(reason: .toolCalls)]
            : [.contentDelta(text: "answer"), .finished(reason: .stop)])
    }

    func executeTool(_ call: Inference.ToolCall) async -> Inference.LocalToolResult {
        .init(toolCallId: call.id, content: "result", isError: false)
    }

    func refreshTools() async -> [Inference.ToolDefinition]? {
        nil
    }

    func classifyFailure(_: Inference.RequestFailure) -> Agent.TurnFailure {
        .terminal
    }
}

func turnInput() -> EiginSDK.Experimental.Agent.ChatInput {
    .init(messages: [], tools: nil, model: "model", initialInstruction: nil,
          allowInterruptionRecovery: true, propagateStreamCancellation: true)
}

func turnCall(_ id: String) -> EiginSDK.Experimental.Inference.ToolCall {
    .init(id: id, kind: "function", name: "lookup", arguments: "{}")
}

func turnRequest(_ values: [EiginSDK.Experimental.Inference.Event]) -> EiginSDK.Experimental.Agent.PreparedRequest {
    let events = TurnEvents(values)
    return .init(providerID: "provider", local: false, services: .init(validate: { _ in }, open: { _, _ in
        .init(next: { await events.next() }, cancel: {})
    }))
}

actor TurnEvents {
    private var values: [EiginSDK.Experimental.Inference.Event]
    init(_ values: [EiginSDK.Experimental.Inference.Event]) {
        self.values = values
    }

    func next() -> EiginSDK.Experimental.Inference.Event? {
        values.isEmpty ? nil : values.removeFirst()
    }
}

actor TurnGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var waiting = false
    func wait() async {
        await withCheckedContinuation { waiting = true; continuation = $0 }
    }

    func release() {
        continuation?.resume(); continuation = nil
    }
}

func waitForTurn(_ condition: @escaping @Sendable () async -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(3)
    while !(await condition()) {
        guard ContinuousClock.now < deadline else { throw TurnTestTimeout() }
        await Task.yield()
    }
}

private struct TurnTestTimeout: Error {}
