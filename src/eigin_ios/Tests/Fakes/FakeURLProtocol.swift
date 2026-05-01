import Foundation

final class FakeURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var _responseMap: [String: (Data, HTTPURLResponse)] = [:]
    private nonisolated(unsafe) static var _errorMap: [String: Error] = [:]

    static func stubResponse(for url: String, data: Data, statusCode: Int) {
        let response = HTTPURLResponse(
            url: URL(string: url)!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        lock.withLock { _responseMap[url] = (data, response) }
    }

    static func stubError(for url: String, error: Error) {
        lock.withLock { _errorMap[url] = error }
    }

    static func fakeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FakeURLProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let urlString = request.url?.absoluteString ?? ""

        let (error, entry) = Self.lock.withLock {
            (Self._errorMap[urlString], Self._responseMap[urlString])
        }

        if let error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }

        if let (data, response) = entry {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        // Default: 404
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 404,
            httpVersion: nil,
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
