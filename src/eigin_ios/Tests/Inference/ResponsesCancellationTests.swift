@testable import Eigin
import Foundation
import Synchronization
import Testing

@Suite("Responses client cancellation")
struct ResponsesCancellationTests {
    @Test(arguments: [false, true], [false, true])
    func cancellingConsumerStopsNetworkWork(bodyPending: Bool, textOnly: Bool) async throws {
        let token = UUID().uuidString
        let probe = PendingInferenceURLProtocol.Probe(sendHeaders: bodyPending)
        PendingInferenceURLProtocol.probes.withLock { $0["Bearer \(token)"] = probe }
        defer {
            _ = PendingInferenceURLProtocol.probes
                .withLock { $0.removeValue(forKey: "Bearer \(token)") }
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PendingInferenceURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let client = ResponsesAPIClient(apiToken: token, session: session)
        let consumed = Mutex(false)
        let task = Task {
            if textOnly {
                let stream = try await client.chatCompletionStream(messages: [], model: "test")
                for try await text in stream {
                    #expect(text == "hello")
                    consumed.withLock { $0 = true }
                }
            } else {
                let stream = try await client.chatCompletionEventStream(messages: [], model: "test")
                for try await event in stream {
                    #expect(event == .contentDelta("hello"))
                    consumed.withLock { $0 = true }
                }
            }
        }
        defer { task.cancel() }
        try await waitUntil { probe.started.withLock { $0 } }
        if bodyPending { try await waitUntil { consumed.withLock { $0 } } }
        task.cancel()
        do {
            try await task.value
            Issue.record("Expected cancellation to reach the consumer")
        } catch is CancellationError {}
        try await waitUntil { probe.stopped.withLock { $0 } }
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !condition() {
            guard ContinuousClock.now < deadline else { throw URLError(.timedOut) }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}
