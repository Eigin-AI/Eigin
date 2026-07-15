import Foundation

/// A `Codable` snapshot of an `HTTPCookie`, so the broker/MitID SSO cookie jar
/// captured at login can be persisted in the Keychain alongside ``AulaSession``
/// and reconstituted later to seed a silent re-authorize (see
/// ``AulaFormWalker/reauthorize``). `HTTPCookie` itself isn't `Codable`.
struct BrokerCookie: Codable, Equatable, Sendable {
    let name: String
    let value: String
    let domain: String
    let path: String
    let isSecure: Bool
    let expiresDate: Date?
}

/// Partitions the cookie jar captured from the login web view into the two
/// things ``AddAulaAccount`` persists: the narrow, API-scoped cookie set
/// (``apiCookies``) that ``AulaAPIClient`` sends on every call, and the full
/// broker/SSO jar (``brokerCookies``) kept only to seed a later silent
/// re-authorize walk. Shared here so connect-time and reauth-time agree on
/// the same shapes.
enum AulaSessionCookies {
    /// API-scoped cookies: non-`login.` `aula.dk` hosts only. A cross-host
    /// `PHPSESSID` from `login.aula.dk` makes Aula treat an API call as an
    /// unknown web session and 401 it instead of falling back to the token,
    /// so it's deliberately excluded here.
    static func apiCookies(from cookies: [HTTPCookie]) -> [String: String] {
        let scoped = cookies.filter { cookie in
            let domain = cookie.domain.lowercased()
            return domain.hasSuffix("aula.dk") && !domain.hasPrefix("login.")
        }
        var result: [String: String] = [:]
        for cookie in scoped {
            result[cookie.name] = cookie.value
        }
        return result
    }

    /// The full jar, unfiltered — includes the broker/`login.aula.dk` and
    /// MitID SSO session cookies a silent re-authorize needs to re-walk the
    /// authorize chain without a fresh MitID prompt.
    static func brokerCookies(from cookies: [HTTPCookie]) -> [BrokerCookie] {
        cookies.map {
            BrokerCookie(
                name: $0.name,
                value: $0.value,
                domain: $0.domain,
                path: $0.path,
                isSecure: $0.isSecure,
                expiresDate: $0.expiresDate
            )
        }
    }

    /// Reconstructs `HTTPCookie`s from a persisted broker jar, to seed
    /// ``URLSessionAulaFormWalkerHTTP`` for a re-authorize attempt.
    static func httpCookies(from brokerCookies: [BrokerCookie]) -> [HTTPCookie] {
        brokerCookies.compactMap { cookie in
            var properties: [HTTPCookiePropertyKey: Any] = [
                .name: cookie.name,
                .value: cookie.value,
                .domain: cookie.domain,
                .path: cookie.path,
            ]
            if cookie.isSecure {
                properties[.secure] = "TRUE"
            }
            if let expiresDate = cookie.expiresDate {
                properties[.expires] = expiresDate
            }
            return HTTPCookie(properties: properties)
        }
    }
}
