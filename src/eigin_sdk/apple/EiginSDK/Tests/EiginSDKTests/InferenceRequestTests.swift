import EiginSDK
import Foundation
import Synchronization
import Testing

private typealias Inference = EiginSDK.Experimental.Inference
private typealias Routing = EiginSDK.Experimental.Routing

@Suite("SDK inference requests")
struct InferenceRequestTests {
    @Test(arguments: [false, true])
    func streamsThroughRequestAndReportsAcceptedOutput(local: Bool) async throws {
        let closed = Mutex(false)
        let events = RequestEvents([.contentDelta(text: "answer"), .finished(reason: .stop)])
        let request = try await start(local: local, services: .init(validate: { _ in }, open: { model, effort in
            #expect(model == "model")
            #expect(effort == nil)
            return .init(next: { await events.next() }, cancel: { closed.withLock { $0 = true } })
        }))
        let first = try #require(try await request.next())
        #expect(first == .contentDelta(text: "answer"))
        try request.observeOutput(first)
        #expect(try await request.next() == .finished(reason: .stop))
        #expect(try await request.next() == nil)
        let report = try #require(try request.report(.succeeded))
        #expect(report.model == "model")
        #expect(report.firstTokenSeconds != nil)
        #expect(try request.selection().retryWon == false)
        #expect(closed.withLock { $0 })
    }

    @Test func reportingRemainsObservableAfterCancellation() async throws {
        let outcomes = Mutex<[Routing.Result]>([])
        let request = try await start(local: false, services: .init(
            validate: { _ in }, open: { _, _ in .init(next: { nil }, cancel: {}) },
            reported: { report, result in
                #expect(report?.model == "model")
                outcomes.withLock { $0.append(result) }
            }
        ))
        request.cancel()
        _ = try request.report(.cancelled)
        #expect(outcomes.withLock { $0 } == [.cancelled])
    }

    @Test func classifiedErrorsSurviveOpenAndRead() async throws {
        let failure = Inference.RequestFailure.Classified(error: .Http(status: 503, body: "upstream"), failure: .notTheModelsFault)
        for opening in [true, false] {
            do {
                let request = try await start(local: opening, services: .init(validate: { _ in }, open: { _, _ in
                    if opening { throw failure }
                    return .init(next: { throw failure }, cancel: {})
                }))
                _ = try await request.next()
                Issue.record("Expected classified failure")
            } catch let error as Inference.RequestFailure { #expect(error == failure) }
        }
    }

    @Test(arguments: ["validate", "open", "read"])
    func cancellationReachesSuspendedHostEffects(phase: String) async throws {
        let entered = Mutex(false)
        let stopped = Mutex(false)
        let nativeClosed = Mutex(false)
        let suspend: @Sendable () async throws -> Void = {
            entered.withLock { $0 = true }
            defer { stopped.withLock { $0 = true } }
            try await Task.sleep(for: .seconds(60))
        }
        let task = Task {
            let request = try await start(local: true, services: .init(validate: { _ in
                if phase == "validate" { try await suspend() }
            }, open: { _, _ in
                if phase == "open" { try await suspend() }
                return .init(next: { try await suspend(); return nil }, cancel: { nativeClosed.withLock { $0 = true } })
            }))
            _ = try await request.next()
        }
        try await waitForRequest { entered.withLock { $0 } }
        task.cancel()
        do { try await task.value; Issue.record("Expected cancellation") } catch is CancellationError {}
        try await waitForRequest { stopped.withLock { $0 } }
        if phase == "read" { #expect(nativeClosed.withLock { $0 }) }
    }

    @Test func lateSessionAfterCancelledOpenIsClosed() async throws {
        let gate = RequestGate()
        let closed = Mutex(false)
        let task = Task {
            try await start(local: true, services: .init(validate: { _ in }, open: { _, _ in
                await gate.wait()
                return .init(next: { nil }, cancel: { closed.withLock { $0 = true } })
            }))
        }
        try await waitForRequest { await gate.isWaiting }
        task.cancel()
        do { _ = try await task.value; Issue.record("Expected cancellation") } catch is CancellationError {}
        await gate.release()
        try await waitForRequest { closed.withLock { $0 } }
    }

    @Test func overlappingReadsDoNotCancelThePendingRead() async throws {
        let gate = RequestGate()
        let closed = Mutex(false)
        let request = try await start(local: true, services: .init(validate: { _ in }, open: { _, _ in
            .init(next: { await gate.wait(); return .contentDelta(text: "answer") }, cancel: { closed.withLock { $0 = true } })
        }))
        let pending = Task { try await request.next() }
        try await waitForRequest { await gate.isWaiting }
        do { _ = try await request.next(); Issue.record("Expected busy") }
        catch Inference.RequestFailure.Inference(.Busy) {}
        #expect(!closed.withLock { $0 })
        await gate.release()
        #expect(try await pending.value == .contentDelta(text: "answer"))
        request.cancel()
    }

    @Test func independentRequestsAndDroppingARequest() async throws {
        let router = Routing.Router.withCatalog()
        let firstClosed = Mutex(false)
        let secondClosed = Mutex(false)
        func services(_ cancel: @escaping @Sendable () -> Void) -> Inference.RequestServices {
            .init(validate: { _ in }, open: { _, _ in
                .init(next: { .contentDelta(text: "answer") }, cancel: cancel)
            })
        }
        var first: Inference.Request? = try await Inference.Request.start(router: router, providerID: "provider", model: "model", local: true, routing: nil, services: services { firstClosed.withLock { $0 = true } })
        let second = try await Inference.Request.start(router: router, providerID: "provider", model: "model", local: true, routing: nil, services: services { secondClosed.withLock { $0 = true } })
        #expect(first != nil)
        first = nil
        try await waitForRequest { firstClosed.withLock { $0 } }
        #expect(!secondClosed.withLock { $0 })
        #expect(try await second.next() == .contentDelta(text: "answer"))
    }

    private func start(local: Bool, services: Inference.RequestServices) async throws -> Inference.Request {
        try await Inference.Request.start(router: Routing.Router.withCatalog(), providerID: "provider", model: "model", local: local, routing: nil, services: services)
    }
}

private actor RequestEvents {
    var events: [Inference.Event]
    init(_ events: [Inference.Event]) {
        self.events = events
    }

    func next() -> Inference.Event? {
        events.isEmpty ? nil : events.removeFirst()
    }
}

private actor RequestGate {
    var isWaiting: Bool {
        continuation != nil
    }

    var continuation: CheckedContinuation<Void, Never>?
    func wait() async {
        await withCheckedContinuation { continuation = $0 }
    }

    func release() {
        continuation?.resume(); continuation = nil
    }
}

private func waitForRequest(_ condition: () async -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(3)
    while !(await condition()) {
        guard ContinuousClock.now < deadline else { throw URLError(.timedOut) }
        try await Task.sleep(for: .milliseconds(5))
    }
}
