import Foundation

/// Minimal HTTP seam for ``DefaultAulaProvider``.
///
/// Aula's unofficial API has no SDK and a couple of load-bearing quirks we
/// must get right — session cookies, the `csrfp-token` header, and bumping the
/// API version when the server retires an old one (HTTP 410). Routing requests
/// through this one-method protocol lets tests assert exactly those behaviors
/// against a fake, rather than standing up `URLProtocol` stubs.
protocol AulaHTTP: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// `URLSession`-backed production implementation.
struct URLSessionAulaHTTP: AulaHTTP {
    let urlSession: URLSession

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AulaProviderError.requestFailed("No HTTP response")
        }
        return (data, http)
    }
}
