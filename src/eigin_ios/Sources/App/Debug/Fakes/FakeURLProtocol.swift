#if DEBUG || EIGIN_DEV
import Foundation

final class FakeURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var _responseMap: [String: (Data, HTTPURLResponse)] = [:]
    private nonisolated(unsafe) static var _errorMap: [String: Error] = [:]
    private nonisolated(unsafe) static var _responseQueues: [String: [(Data, HTTPURLResponse)]] =
        [:]
    private nonisolated(unsafe) static var _capturedBodies: [String: Data] = [:]
    private nonisolated(unsafe) static var _capturedRanges: [String: [String]] = [:]
    private nonisolated(unsafe) static var _delays: [String: TimeInterval] = [:]
    private nonisolated(unsafe) var isStopped = false

    /// Hold `url`'s stubbed response for `seconds`, so a test can act while the
    /// request is in flight (e.g. cancel it).
    static func stubDelay(for url: String, seconds: TimeInterval) {
        lock.withLock { _delays[url] = seconds }
    }

    /// Every `Range` header value received for `url`, in arrival order.
    static func requestedRanges(for url: String) -> [String] {
        lock.withLock { _capturedRanges[url] ?? [] }
    }

    /// The most recent request body sent to `url`, for asserting what the client serialized.
    static func lastRequestBody(for url: String) -> Data? {
        lock.withLock { _capturedBodies[url] }
    }

    /// Queue a response for a URL. Queued responses are consumed in FIFO order across successive
    /// requests to the same URL, letting one endpoint return e.g. 402 then 200 to exercise
    /// failover.
    /// Takes precedence over `stubResponse` while the queue is non-empty.
    static func enqueueResponse(for url: String, data: Data, statusCode: Int) {
        let response = HTTPURLResponse(
            url: URL(string: url)!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        lock.withLock { _responseQueues[url, default: []].append((data, response)) }
    }

    static func stubResponse(
        for url: String,
        data: Data,
        statusCode: Int,
        headers: [String: String] = [:]
    ) {
        let response = HTTPURLResponse(
            url: URL(string: url)!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: headers
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

        if let body = Self.readBody(from: request) {
            Self.lock.withLock { Self._capturedBodies[urlString] = body }
        }

        if let delay = Self.lock.withLock({ Self._delays[urlString] }) {
            DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [self] in
                if !isStopped { deliver(urlString) }
            }
            return
        }
        deliver(urlString)
    }

    private func deliver(_ urlString: String) {
        let error: Error?
        let queued: (Data, HTTPURLResponse)?
        let entry: (Data, HTTPURLResponse)?
        Self.lock.lock()
        error = Self._errorMap[urlString]
        entry = Self._responseMap[urlString]
        if var queue = Self._responseQueues[urlString], !queue.isEmpty {
            queued = queue.removeFirst()
            Self._responseQueues[urlString] = queue
        } else {
            queued = nil
        }
        Self.lock.unlock()

        if let error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }

        if let (data, response) = queued {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        if let (data, response) = entry {
            // Honour byte ranges on 200 stubs the way an object store would.
            if let range = request.value(forHTTPHeaderField: "Range") {
                Self.lock.withLock { Self._capturedRanges[urlString, default: []].append(range) }
                if response.statusCode == 200, let (slice, partial) = Self.slice(
                    data,
                    range: range,
                    url: request.url!
                ) {
                    client?.urlProtocol(self, didReceive: partial, cacheStoragePolicy: .notAllowed)
                    client?.urlProtocol(self, didLoad: slice)
                    client?.urlProtocolDidFinishLoading(self)
                    return
                }
            }
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

    override func stopLoading() {
        isStopped = true
    }

    /// `bytes=a-b` → (data[a...b], 206 response with Content-Range).
    private static func slice(_ data: Data, range: String, url: URL) -> (Data, HTTPURLResponse)? {
        let bounds = range.dropFirst("bytes=".count).split(separator: "-").compactMap { Int($0) }
        guard bounds.count == 2, bounds[0] <= bounds[1], bounds[1] < data.count else { return nil }
        let slice = data.subdata(in: bounds[0] ..< bounds[1] + 1)
        let response = HTTPURLResponse(
            url: url, statusCode: 206, httpVersion: nil,
            headerFields: ["Content-Range": "bytes \(bounds[0])-\(bounds[1])/\(data.count)"]
        )!
        return (slice, response)
    }

    /// URLSession often moves `httpBody` into `httpBodyStream` before a URLProtocol sees it,
    /// so fall back to draining the stream when the body isn't set directly.
    private static func readBody(from request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data.isEmpty ? nil : data
    }
}
#endif
