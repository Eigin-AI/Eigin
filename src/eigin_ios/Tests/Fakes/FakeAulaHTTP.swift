@testable import Eigin
import Foundation

/// Scriptable ``AulaHTTP`` fake for tests. A closure maps each request to a
/// status code and body, so a test can key responses on the `method` query
/// param or return a 410 then a 200 to exercise the version-bump retry. All
/// requests are recorded so tests can assert on the cookie/csrf/auth headers
/// and the URL the provider actually built.
final class FakeAulaHTTP: AulaHTTP, @unchecked Sendable {
    private let handler: @Sendable (URLRequest) -> (Int, Data)
    private let headerHandler: (@Sendable (URLRequest) -> [String: String])?
    private let lock = NSLock()
    private var recorded: [URLRequest] = []

    init(handler: @escaping @Sendable (URLRequest) -> (Int, Data)) {
        self.handler = handler
        headerHandler = nil
    }

    /// Variant that also scripts response headers, for exercising the
    /// `Set-Cookie` rotation the client folds back into the session.
    init(
        handler: @escaping @Sendable (URLRequest) -> (Int, Data),
        headers headerHandler: @escaping @Sendable (URLRequest) -> [String: String]
    ) {
        self.handler = handler
        self.headerHandler = headerHandler
    }

    var requests: [URLRequest] {
        lock.withLock { recorded }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.withLock { recorded.append(request) }
        let (code, data) = handler(request)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: code,
            httpVersion: nil,
            headerFields: headerHandler?(request)
        )!
        return (data, response)
    }
}

extension URLRequest {
    /// The Aula `method` query param, for keying fake responses in tests.
    var aulaMethod: String? {
        guard let url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        return components.queryItems?.first { $0.name == "method" }?.value
    }
}
