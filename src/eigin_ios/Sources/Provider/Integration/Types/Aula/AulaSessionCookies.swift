import Foundation

/// Narrows the cookie jar captured from the login web view down to the
/// API-scoped cookie set (``apiCookies``) that ``AulaAPIClient`` sends on
/// every call. Shared so connect-time and the provider's web-session reset
/// agree on the same shape.
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
}
