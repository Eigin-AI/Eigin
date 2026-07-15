import Foundation

/// An unofficial client for Aula's JSON API. It attaches the login session
/// cookies, the `access_token` as a query param (Aula's API quirk — it
/// rejects an `Authorization: Bearer` header), and `csrfp-token`, and bumps
/// the API version on HTTP 410 (Aula retires old versions) then retries.
/// Storage-agnostic: it returns the (possibly version-bumped) session so the
/// caller can persist it.
/// One response from ``AulaAPIClient``, carrying the session as it stood
/// after the request: Aula rotates cookies and we bump the API version
/// mid-flight, so the session that made a call successfully isn't always the
/// one the caller started with. Persist this one so the next call sends what
/// Aula actually expects.
struct AulaResponse {
    let data: Data
    let session: AulaSession
}

struct AulaAPIClient: Sendable {
    let http: any AulaHTTP

    static let baseURL = "https://www.aula.dk"

    /// Aula's active API version drifts over time, and a retired one 410s. How
    /// many version bumps we'll follow chasing that before giving up.
    static let maxVersionBumps = 6

    /// Performs a GET against `…/api/v{version}/?method=<method>&…`.
    func get(
        method: String,
        queryItems: [URLQueryItem] = [],
        session: AulaSession
    ) async throws -> AulaResponse {
        try await perform(session: session) { current in
            try Self.buildRequest(
                method: method,
                queryItems: queryItems,
                jsonBody: nil,
                session: current
            )
        }
    }

    /// Performs a POST against `…/api/v{version}/?method=<method>` with a JSON
    /// body. Some methods (e.g. `calendar.getEventsByProfileIdsAndResourceIds`)
    /// take their arguments as a JSON payload rather than query params and
    /// reject the GET form with a `400`.
    func post(
        method: String,
        jsonBody: [String: Any],
        session: AulaSession
    ) async throws -> AulaResponse {
        let body = try JSONSerialization.data(withJSONObject: jsonBody)
        return try await perform(session: session) { current in
            try Self.buildRequest(
                method: method,
                queryItems: [],
                jsonBody: body,
                session: current
            )
        }
    }

    /// The shared request loop: builds the request for the current session,
    /// folds Aula's rotated cookies back in, and bumps the API version on 410.
    private func perform(
        session: AulaSession,
        makeRequest: (AulaSession) throws -> URLRequest
    ) async throws -> AulaResponse {
        var current = session

        for _ in 0 ... Self.maxVersionBumps {
            let request = try makeRequest(current)
            let (data, response) = try await http.send(request)
            // Aula rotates the `PHPSESSID` web session on every response — the
            // cookie we sent is single-use. Fold the rotated cookies back in
            // *before* returning or retrying, so the session we hand back (and
            // the caller persists) carries the value the next call must send.
            // Without this the first call after connect always 401s.
            current = Self.absorbingCookies(from: response, requestURL: request.url, into: current)

            switch response.statusCode {
            case 200 ... 299:
                return AulaResponse(data: data, session: current)
            case 410:
                current.apiVersion += 1
            case 401, 403:
                throw AulaProviderError.sessionExpired
            case 404:
                throw AulaProviderError.notFound
            default:
                throw AulaProviderError.requestFailed("HTTP \(response.statusCode)")
            }
        }
        throw AulaProviderError.requestFailed("No supported API version found")
    }

    static func buildRequest(
        method: String,
        queryItems: [URLQueryItem],
        jsonBody: Data?,
        session: AulaSession
    ) throws -> URLRequest {
        var components = URLComponents(string: "\(baseURL)/api/v\(session.apiVersion)/")!
        var items = [URLQueryItem(name: "method", value: method)]
        // The access token travels as a query param even on POSTs (Aula rejects
        // an `Authorization: Bearer` header); the JSON payload is the body.
        if let accessToken = session.accessToken {
            items.append(URLQueryItem(name: "access_token", value: accessToken))
        }
        components.queryItems = items + queryItems
        guard let url = components.url else {
            throw AulaProviderError.requestFailed("Failed to build request URL")
        }

        var request = URLRequest(url: url)
        let isPost = jsonBody != nil
        request.httpMethod = isPost ? "POST" : "GET"
        if let jsonBody {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = jsonBody
            // Mirror the reference app client: the CSRF token rides only on
            // POSTs (state-changing calls), read from the `Csrfp-Token` cookie.
            if let csrf = session.csrfToken {
                request.setValue(csrf, forHTTPHeaderField: "csrfp-token")
            }
        }
        // Send only the cookies Aula itself issued for the API host (folded in
        // from earlier responses via `absorbingCookies`). We deliberately do
        // *not* replay the login-walk session cookies here: the token is the
        // credential, and a cross-host `PHPSESSID` from `login.aula.dk` makes
        // Aula treat the call as an unknown web session and 401 it instead of
        // falling back to the token.
        if !session.cookies.isEmpty {
            let cookieHeader = session.cookies
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: "; ")
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }
        return request
    }

    /// Merges any `Set-Cookie` from `response` into `session.cookies`, keeping
    /// the previous values for cookies the response didn't touch. Only aula.dk
    /// cookies are kept — the API is same-origin, so nothing else should be set
    /// here, and this guards against ever persisting a third-party cookie.
    static func absorbingCookies(
        from response: HTTPURLResponse,
        requestURL: URL?,
        into session: AulaSession
    ) -> AulaSession {
        guard let url = requestURL,
              let headers = response.allHeaderFields as? [String: String]
        else { return session }

        let setCookies = HTTPCookie.cookies(withResponseHeaderFields: headers, for: url)
            .filter { $0.domain.lowercased().hasSuffix("aula.dk") }
        guard !setCookies.isEmpty else { return session }

        var updated = session
        for cookie in setCookies {
            updated.cookies[cookie.name] = cookie.value
        }
        return updated
    }
}
