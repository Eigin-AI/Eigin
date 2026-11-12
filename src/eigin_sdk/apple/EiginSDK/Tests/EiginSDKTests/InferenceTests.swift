import EiginSDK
import Foundation
import Synchronization
import Testing

@Suite("Apple inference cancellation")
struct InferenceTests {
    @Test func missingRelayKeyFailsDuringConstruction() {
        #expect(throws: EiginSDK.Experimental.Inference.Failure.self) {
            _ = try EiginSDK.Experimental.Inference.EiginRelay(
                configuration: .init(baseUrl: "https://configuration.test", relayKey: ""),
                walletSource: CancellationWallets()
            )
        }
    }

    @Test(arguments: [false, true], [false, true])
    func taskCancellationStopsURLSession(beforeBody: Bool, relay: Bool) async throws {
        let probe = CancellationProbe(sendHeaders: beforeBody)
        let id = UUID().uuidString
        CancellationURLProtocol.probes.withLock { $0[id] = probe }
        defer { CancellationURLProtocol.probes.withLock { $0.removeValue(forKey: id) } }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CancellationURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let open: @Sendable (EiginSDK.Experimental.Inference.Input) async throws -> EiginSDK.Experimental.Inference.Stream
        if relay {
            let provider = try EiginSDK.Experimental.Inference.EiginRelay(
                configuration: .init(baseUrl: "https://cancellation.test/\(id)", relayKey: "relay-key"),
                walletSource: CancellationWallets(), session: session
            )
            open = { try await provider.stream($0) }
        } else {
            let provider = EiginSDK.Experimental.Inference.OpenAICompatible(configuration: .init(
                baseUrl: "https://cancellation.test/\(id)", apiToken: "test", extraHeaders: [:]
            ), session: session)
            open = { try await provider.stream($0) }
        }

        let reading = Mutex(false)
        let task = Task {
            let stream = try await open(.init(model: "test", messages: [], tools: nil, reasoningEffort: nil, promptCacheKey: nil, modelFamily: nil, isRelay: false, reasoningOrigin: nil, textOnly: false))
            reading.withLock { $0 = true }
            _ = try await stream.next()
        }
        try await waitUntil { probe.started.withLock { $0 } }
        if beforeBody { try await waitUntil { reading.withLock { $0 } } }
        task.cancel()
        do {
            try await task.value
            Issue.record("Expected Swift task cancellation")
        } catch is CancellationError {}
        try await waitUntil { probe.stopped.withLock { $0 } }
    }
}

private func waitUntil(_ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(3)
    while !condition() {
        guard ContinuousClock.now < deadline else {
            throw URLError(.timedOut)
        }
        try await Task.sleep(for: .milliseconds(5))
    }
}

private final class CancellationProbe: Sendable {
    let sendHeaders: Bool
    let started = Mutex(false)
    let stopped = Mutex(false)

    init(sendHeaders: Bool) {
        self.sendHeaders = sendHeaders
    }
}

private final class CancellationURLProtocol: URLProtocol, @unchecked Sendable {
    static let probes = Mutex<[String: CancellationProbe]>([:])
    private var probe: CancellationProbe?

    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let id = request.url!.pathComponents[1]
        probe = Self.probes.withLock { $0[id] }
        if probe?.sendHeaders == true {
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                           headerFields: ["Content-Type": "text/event-stream"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        }
        probe?.started.withLock { $0 = true }
    }

    override func stopLoading() {
        probe?.stopped.withLock { $0 = true }
    }
}

private final class CancellationWallets: EiginSDK.Experimental.Inference.EiginRelayWalletSource {
    func nextToken(excluded: [String]) throws -> String? {
        excluded.isEmpty ? "token" : nil
    }

    func markExhausted(token _: String) throws {
        Issue.record("Cancellation must not exhaust a wallet")
    }
}
