import Foundation
import Synchronization

/// Holds response headers or body data until the consumer cancels its request.
final class PendingInferenceURLProtocol: URLProtocol, @unchecked Sendable {
    final class Probe: Sendable {
        let sendHeaders: Bool
        let started = Mutex(false)
        let stopped = Mutex(false)

        init(sendHeaders: Bool) {
            self.sendHeaders = sendHeaders
        }
    }

    static let probes = Mutex<[String: Probe]>([:])
    private var probe: Probe?

    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let token = request.value(forHTTPHeaderField: "Authorization") ?? ""
        probe = Self.probes.withLock { $0[token] }
        if probe?.sendHeaders == true {
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "text/event-stream"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(
                self,
                didLoad: Data(
                    "data: {\"type\":\"response.output_text.delta\",\"delta\":\"hello\"}\n\n"
                        .utf8
                )
            )
        }
        probe?.started.withLock { $0 = true }
    }

    override func stopLoading() {
        probe?.stopped.withLock { $0 = true }
    }
}
