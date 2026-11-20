#if DEBUG || EIGIN_DEV
import Foundation

/// A slow HTTP response used to check absolute download deadlines during streaming.
final class FakeAttachmentStreamURLProtocol: URLProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        deliver(remaining: 40)
    }

    private func deliver(remaining: Int) {
        guard !lock.withLock({ stopped }) else { return }
        if remaining == 0 {
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        client?.urlProtocol(self, didLoad: Data([65]))
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) { [self] in
            deliver(remaining: remaining - 1)
        }
    }

    override func stopLoading() {
        lock.withLock { stopped = true }
    }
}
#endif
