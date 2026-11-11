import EiginSDKBindings
import Foundation

/// Uses the supplied session’s timeout, trust and proxy settings with same-origin redirects.
final class URLSessionHTTPTransport: HttpTransport, @unchecked Sendable {
    private let session: URLSession
    private let lock = NSLock()
    private var exchanges: [UInt64: URLSessionExchange] = [:]

    init(session: URLSession) {
        self.session = session
    }

    func startRequest(id: UInt64, request: HttpRequest, completion: HttpResponseHeadCallback) {
        guard let url = URL(string: request.url) else {
            completion.fail(reason: "Invalid HTTP URL")
            return
        }
        var native = URLRequest(url: url)
        native.httpMethod = request.method
        native.httpBody = request.body.isEmpty ? nil : request.body
        for (key, value) in request.headers {
            native.setValue(value, forHTTPHeaderField: key)
        }
        let exchange = URLSessionExchange(session: session, request: native, head: completion)
        lock.withLock { exchanges[id] = exchange }
        exchange.start()
    }

    func read(id: UInt64, completion: HttpBodyChunkCallback) {
        guard let exchange = lock.withLock({ exchanges[id] }) else {
            completion.fail(reason: "HTTP response closed")
            return
        }
        exchange.read(completion)
    }

    func close(id: UInt64) {
        let exchange = lock.withLock { exchanges.removeValue(forKey: id) }
        exchange?.close()
    }
}

/// One bounded response buffer; task delegates preserve injected session configuration.
private final class URLSessionExchange: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let session: URLSession
    private let request: URLRequest
    private let head: HttpResponseHeadCallback
    private let lock = NSLock()
    private var task: URLSessionDataTask?
    private var pending: HttpBodyChunkCallback?
    private var buffer = Data()
    private var finished = false
    private var closed = false
    private var suspended = false
    private var failure: String?
    private var networkError: NSError?

    init(session: URLSession, request: URLRequest, head: HttpResponseHeadCallback) {
        self.session = session
        self.request = request
        self.head = head
    }

    func start() {
        lock.withLock {
            guard !closed else { return }
            let task = session.dataTask(with: request)
            task.delegate = self
            self.task = task
            task.resume()
        }
    }

    func read(_ completion: HttpBodyChunkCallback) {
        var bytes: Data?
        var error: String?
        var nativeError: NSError?
        var eof = false
        lock.withLock {
            if closed { error = "HTTP response closed"; return }
            if pending != nil { error = "HTTP read already pending"; return }
            if !buffer.isEmpty {
                let count = min(buffer.count, 64 * 1024)
                bytes = Data(buffer.prefix(count))
                buffer.removeFirst(count)
                if suspended, buffer.count < 64 * 1024 { suspended = false; task?.resume() }
            } else if let failure { error = failure; nativeError = networkError }
            else if finished { eof = true }
            else { pending = completion }
        }
        if let nativeError { completion.failWithCode(reason: nativeError.localizedDescription, domain: nativeError.domain, code: Int64(nativeError.code)) }
        else if let error { completion.fail(reason: error) }
        else if let bytes { completion.succeed(bytes: bytes) }
        else if eof { completion.succeed(bytes: nil) }
    }

    func close() {
        let resources = lock.withLock { () -> (URLSessionDataTask?, HttpBodyChunkCallback?) in
            guard !closed else { return (nil, nil) }
            closed = true
            let result = (task, pending)
            task = nil
            pending = nil
            buffer = Data()
            return result
        }
        resources.0?.cancel()
        resources.1?.fail(reason: "HTTP response closed")
        head.fail(reason: "HTTP response closed")
    }

    func urlSession(
        _: URLSession, dataTask _: URLSessionDataTask, didReceive response: URLResponse,
        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
    ) {
        guard let http = response as? HTTPURLResponse else {
            head.fail(reason: "Non-HTTP response")
            completionHandler(.cancel)
            return
        }
        if lock.withLock({ closed }) { completionHandler(.cancel); return }
        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            headers[String(describing: key).lowercased()] = String(describing: value)
        }
        head.succeed(head: HttpResponseHead(status: UInt16(http.statusCode), headers: headers))
        completionHandler(.allow)
    }

    func urlSession(
        _: URLSession, task _: URLSessionTask, willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        guard let original = request.url, let redirected = newRequest.url else { completionHandler(nil); return }
        func origin(_ url: URL) -> String {
            "\(url.scheme?.lowercased() ?? "")://\(url.host?.lowercased() ?? ""):\(url.port ?? (url.scheme?.lowercased() == "https" ? 443 : 80))"
        }
        completionHandler(origin(original) == origin(redirected) ? newRequest : nil)
    }

    func urlSession(_: URLSession, dataTask _: URLSessionDataTask, didReceive data: Data) {
        var delivery: (HttpBodyChunkCallback, Data)?
        var abort: URLSessionDataTask?
        lock.withLock {
            guard !closed else { return }
            if buffer.count + data.count > 1024 * 1024 {
                failure = "HTTP buffer exceeds 1 MiB"
                abort = task
                return
            }
            buffer.append(data)
            if let pending {
                let count = min(buffer.count, 64 * 1024)
                delivery = (pending, Data(buffer.prefix(count)))
                buffer.removeFirst(count)
                self.pending = nil
            }
            if buffer.count >= 64 * 1024, !suspended { suspended = true; task?.suspend() }
        }
        abort?.cancel()
        if let (completion, bytes) = delivery { completion.succeed(bytes: bytes) }
    }

    func urlSession(_: URLSession, task _: URLSessionTask, didCompleteWithError error: (any Error)?) {
        let result = lock.withLock { () -> (HttpBodyChunkCallback?, String?, NSError?) in
            guard !closed else { return (nil, nil, nil) }
            finished = true
            if failure == nil, let error { failure = error.localizedDescription; networkError = error as NSError }
            let result = (pending, failure, networkError)
            pending = nil
            return result
        }
        if let error = result.2 {
            head.failWithCode(reason: error.localizedDescription, domain: error.domain, code: Int64(error.code))
            result.0?.failWithCode(reason: error.localizedDescription, domain: error.domain, code: Int64(error.code))
        } else if let failure = result.1 { head.fail(reason: failure); result.0?.fail(reason: failure) }
        else { result.0?.succeed(bytes: nil) }
    }
}
