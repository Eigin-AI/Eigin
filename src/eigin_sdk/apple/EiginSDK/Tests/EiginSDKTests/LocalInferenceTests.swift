import EiginSDK
import Foundation
import Synchronization
import Testing

private typealias Inference = EiginSDK.Experimental.Inference

@Suite("Host local inference")
struct LocalInferenceTests {
    private func input() -> Inference.Input {
        .init(model: "gemma", messages: [], tools: nil, reasoningEffort: nil,
              promptCacheKey: nil, modelFamily: .google, isRelay: false, reasoningOrigin: nil, textOnly: false)
    }

    @Test func streamsAndExecutesReentrantToolsThroughRust() async throws {
        let router = EiginSDK.Experimental.Routing.Router.withCatalog()
        let closed = Mutex(false)
        let provider = Inference.Local { request, tools in
            #expect(request.model == "gemma")
            let tools = try #require(tools)
            let result = try await tools.execute(call: .init(id: "call", kind: "function", name: "lookup", arguments: "{}"))
            #expect(result.toolCallId == "call")
            #expect(!result.isError)
            let events = LocalEvents([.contentDelta(text: result.content), .finished(reason: .stop)])
            return .init(next: { await events.next() }, cancel: { closed.withLock { $0 = true } })
        }
        let stream = try await provider.stream(input(), executeTool: { call in
            router.recordReachability(reachable: false)
            return .init(toolCallId: call.id, content: "answer", isError: false)
        })
        #expect(try await stream.next() == .contentDelta(text: "answer"))
        #expect(try await stream.next() == .finished(reason: .stop))
        #expect(try await stream.next() == nil)
        #expect(closed.withLock { $0 })
    }

    @Test(arguments: ["open", "read", "tool"])
    func cancellationReachesSuspendedHostWork(phase: String) async throws {
        let started = Mutex(false)
        let stopped = Mutex(false)
        let nativeClosed = Mutex(false)
        let suspend: @Sendable () async throws -> Void = {
            started.withLock { $0 = true }
            defer { stopped.withLock { $0 = true } }
            try await Task.sleep(for: .seconds(60))
        }
        let provider = Inference.Local { _, tools in
            if phase == "open" { try await suspend() }
            if phase == "tool" {
                _ = try await tools?.execute(call: .init(id: "call", kind: "function", name: "lookup", arguments: "{}"))
            }
            return .init(next: { try await suspend(); return nil }, cancel: { nativeClosed.withLock { $0 = true } })
        }
        let input = input()
        let task = Task {
            let stream = try await provider.stream(input, executeTool: { call in
                try await suspend()
                return .init(toolCallId: call.id, content: "unused", isError: false)
            })
            _ = try await stream.next()
        }
        try await waitForLocal { started.withLock { $0 } }
        task.cancel()
        do { try await task.value; Issue.record("Expected cancellation") }
        catch is CancellationError {}
        try await waitForLocal { stopped.withLock { $0 } }
        if phase == "read" { #expect(nativeClosed.withLock { $0 }) }
    }

    @Test func typedAvailabilityFailureSurvivesBindings() async throws {
        let provider = Inference.Local { _, _ in
            throw Inference.Failure.LocalUnavailable(code: "not_downloaded", reason: "Download Gemma")
        }
        do { _ = try await provider.stream(input()); Issue.record("Expected availability failure") }
        catch let Inference.Failure.LocalUnavailable(code, reason) {
            #expect(code == "not_downloaded")
            #expect(reason == "Download Gemma")
        }
    }

    @Test func droppingStreamClosesNativeSession() async throws {
        let closed = Mutex(false)
        let provider = Inference.Local { _, _ in
            .init(next: { nil }, cancel: { closed.withLock { $0 = true } })
        }
        var stream: Inference.Stream? = try await provider.stream(input())
        #expect(stream != nil)
        stream = nil
        try await waitForLocal { closed.withLock { $0 } }
    }
}

private actor LocalEvents {
    var events: [Inference.Event]
    init(_ events: [Inference.Event]) {
        self.events = events
    }

    func next() -> Inference.Event? {
        events.isEmpty ? nil : events.removeFirst()
    }
}

private func waitForLocal(_ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(3)
    while !condition() {
        guard ContinuousClock.now < deadline else { throw URLError(.timedOut) }
        try await Task.sleep(for: .milliseconds(5))
    }
}
