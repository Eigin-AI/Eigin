import Foundation

/// A single hop's response in the manual-redirect walk: enough to inspect a
/// `3xx`'s `Location` or a `200`'s HTML body without `URLSession` following
/// redirects on our behalf.
struct AulaFormWalkerResponse {
    let statusCode: Int
    /// The URL this response is *for* (i.e. the request URL), used to resolve
    /// relative `Location`/form-`action` values.
    let url: URL
    /// The resolved, absolute `Location`, present only for `3xx` responses.
    let location: URL?
    let body: String
}

/// Manual-redirect HTTP seam for ``AulaFormWalker``, analogous to ``AulaHTTP``.
/// Never auto-follows redirects — the walker needs to inspect each hop itself,
/// since some hops are `3xx`s to follow and others are `200` HTML pages
/// carrying a form to resubmit.
protocol AulaFormWalkerHTTP: Sendable {
    /// - Parameter referer: the page the form was read from. Sent as both
    ///   `Referer` and `Origin` — the broker's SAML endpoint rejects the POST
    ///   (observed as a `500`) without them, mirroring the `Origin`/`Referer`
    ///   a real browser sends on a same-flow form submission.
    func post(
        _ url: URL,
        form: [String: String],
        referer: URL
    ) async throws -> AulaFormWalkerResponse
    func get(_ url: URL) async throws -> AulaFormWalkerResponse
}

/// `URLSession`-backed production implementation. Redirects are disabled at
/// the delegate level (`willPerformHTTPRedirection` returns `nil`) so every
/// `3xx` comes back as a normal response with its `Location` header intact,
/// rather than being followed transparently.
final class URLSessionAulaFormWalkerHTTP: NSObject, AulaFormWalkerHTTP, URLSessionTaskDelegate,
    @unchecked Sendable
{
    private var session: URLSession!
    /// The real WKWebView session's `navigator.userAgent` (see the
    /// integration doc for why this must match across the headless hops).
    private let userAgent: String?

    /// - Parameter cookies: session cookies captured from the interactive
    ///   web-view login, seeded into a fresh ephemeral cookie jar so the walk
    ///   continues that browser session rather than starting a new one.
    init(cookies: [HTTPCookie], userAgent: String? = nil) {
        self.userAgent = userAgent
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = true
        // `.always` (not the default `.onlyFromMainDocumentDomain`) so the
        // `.aula.dk` parent-domain session cookie set on the login→portal
        // redirects isn't silently dropped.
        configuration.httpCookieAcceptPolicy = .always
        // Seed into the ephemeral config's own cookie store — a bare
        // `HTTPCookieStorage()` is inert and silently drops every cookie.
        if let storage = configuration.httpCookieStorage {
            storage.cookieAcceptPolicy = .always
            for cookie in cookies {
                storage.setCookie(cookie)
            }
        }
        super.init()
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    /// All cookies accumulated in the walk's jar so far — the final read of
    /// this after the walk completes is what gets persisted alongside the
    /// tokens (it includes `Csrfp-Token` etc. set along the way).
    var currentCookies: [HTTPCookie] {
        session.configuration.httpCookieStorage?.cookies ?? []
    }

    func post(
        _ url: URL,
        form: [String: String],
        referer: URL
    ) async throws -> AulaFormWalkerResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(
            "application/x-www-form-urlencoded",
            forHTTPHeaderField: "Content-Type"
        )
        request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer")
        if let scheme = referer.scheme, let host = referer.host {
            let origin = "\(scheme)://\(host)" + (referer.port.map { ":\($0)" } ?? "")
            request.setValue(origin, forHTTPHeaderField: "Origin")
        }
        request.httpBody = Self.formEncode(form).data(using: .utf8)
        return try await send(request)
    }

    func get(_ url: URL) async throws -> AulaFormWalkerResponse {
        try await send(URLRequest(url: url))
    }

    private func send(_ requestIn: URLRequest) async throws -> AulaFormWalkerResponse {
        var request = requestIn
        if let userAgent {
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue(
                "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
                forHTTPHeaderField: "Accept"
            )
            request.setValue("1", forHTTPHeaderField: "Upgrade-Insecure-Requests")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, let url = request.url else {
            throw AulaConnectionError.unexpectedResponse
        }

        var location: URL?
        if (300 ... 399).contains(http.statusCode),
           let raw = http.value(forHTTPHeaderField: "Location")
        {
            location = URL(string: raw, relativeTo: url)?.absoluteURL
        }

        let body = String(data: data, encoding: .utf8) ?? ""
        return AulaFormWalkerResponse(
            statusCode: http.statusCode,
            url: url,
            location: location,
            body: body
        )
    }

    // MARK: - URLSessionTaskDelegate

    /// Disables automatic redirect-following: returning `nil` makes
    /// `URLSession` complete the task with the `3xx` response itself, instead
    /// of transparently issuing the follow-up request.
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }

    /// `application/x-www-form-urlencoded` percent-encoding using only the
    /// unreserved set (RFC 3986 §2.3) — deliberately not `.urlQueryAllowed`,
    /// which treats `+` as a literal and corrupts base64 SAML responses (see
    /// `docs/src/integrations/aula.md`).
    private static func formEncode(_ params: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return params.map { key, value in
            let escapedKey = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let escapedValue = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(escapedKey)=\(escapedValue)"
        }.joined(separator: "&")
    }
}
