import EiginSDK
import Foundation
import Synchronization
import Testing

private typealias Inference = EiginSDK.Experimental.Inference
private typealias Routing = EiginSDK.Experimental.Routing

@Suite("Request routing callbacks")
struct RequestRoutingTests {
    @Test func rustSelectsReplacementAfterCatalogAndHealthCallbacks() async throws {
        let input = routing()
        let calls = Mutex<[String]>([])
        let events = Mutex<[Inference.Event]>([.contentDelta(text: "replacement answer"), .finished(reason: .stop)])
        let request = try await Inference.Request.start(
            router: Routing.Router.withCatalog(), providerID: "provider", model: input.currentModel,
            local: false, routing: input, services: .init(validate: { model in
                calls.withLock { $0.append("validate:\(model)") }
            }, open: { model, _ in
                calls.withLock { $0.append("open:\(model)") }
                if model == input.currentModel { throw missingModel() }
                return .init(next: { events.withLock { $0.isEmpty ? nil : $0.removeFirst() } }, cancel: {})
            }, refreshCatalog: { _ in
                calls.withLock { $0.append("catalog") }
                return input.inventory
            }, refreshHealth: { _ in
                calls.withLock { $0.append("health") }
                return []
            }, now: { Date(timeIntervalSince1970: 0) })
        )
        #expect(try await request.next() == .contentDelta(text: "replacement answer"))
        let selection = try request.selection()
        #expect(selection.model == "gpt-4.1-mini")
        #expect(selection.retryWon)
        #expect(calls.withLock { $0 } == ["validate:gpt-4.1", "open:gpt-4.1", "catalog", "health", "validate:gpt-4.1-mini", "open:gpt-4.1-mini"])
    }

    @Test(arguments: ["catalog", "health"])
    func cancellationDoesNotWaitForNoncooperativeRefresh(phase: String) async throws {
        let input = routing()
        let entered = Mutex(false)
        let cancelled = Mutex(false)
        let opened = Mutex<[String]>([])
        let gate = RefreshGate()
        let suspend: @Sendable () async -> Void = {
            await withTaskCancellationHandler {
                entered.withLock { $0 = true }
                await gate.wait()
            } onCancel: { cancelled.withLock { $0 = true } }
        }
        let task = Task {
            let request = try await Inference.Request.start(
                router: Routing.Router.withCatalog(), providerID: "provider", model: input.currentModel,
                local: false, routing: input, services: .init(validate: { _ in }, open: { model, _ in
                    opened.withLock { $0.append(model) }
                    throw missingModel()
                }, refreshCatalog: { _ in
                    if phase == "catalog" { await suspend() }
                    return input.inventory
                }, refreshHealth: { _ in
                    if phase == "health" { await suspend() }
                    return []
                })
            )
            _ = try await request.next()
        }
        let deadline = ContinuousClock.now + .seconds(3)
        while !entered.withLock({ $0 }) {
            guard ContinuousClock.now < deadline else { throw URLError(.timedOut) }
            try await Task.sleep(for: .milliseconds(5))
        }
        task.cancel()
        do { try await task.value; Issue.record("Expected cancellation") } catch is CancellationError {}
        #expect(cancelled.withLock { $0 })
        await gate.release()
        #expect(opened.withLock { $0 } == [input.currentModel])
    }
}

private func missingModel() -> Inference.RequestFailure {
    .Classified(error: .Http(status: 404, body: "model_not_found"), failure: .modelNotFound)
}

private func routing() -> Routing.Request {
    .init(providerId: "provider", currentModel: "gpt-4.1", automatic: true, conversationId: nil,
          messageNeedsReasoning: false, requirements: .init(needsTools: true, needsVision: false, promptTokens: 100),
          inventory: .init(providerId: "provider", baseUrl: "https://provider.test/v1", available: ["gpt-4.1", "gpt-4.1-mini"], enabled: [], models: []))
}

private actor RefreshGate {
    var released = false
    var continuation: CheckedContinuation<Void, Never>?
    func wait() async {
        guard !released else { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func release() {
        released = true; continuation?.resume(); continuation = nil
    }
}
