import Foundation

/// Result of a successful silent re-authorize: fresh tokens (when the walk
/// reached the OIDC callback) and the re-warmed cookie jar, mirroring
/// ``AulaFormWalker/Result``.
struct AulaReauthResult: Sendable {
    let tokens: TokenResponse?
    let cookies: [HTTPCookie]
}

/// Recovers a lapsed Aula session without an interactive MitID login, by
/// re-walking the OIDC authorize chain against the broker/SSO cookies
/// captured at the original login (``AulaSession/brokerCookies``). If that
/// broker session is still alive, the chain silently SSOs and mints a fresh
/// code — restoring both the MitID step-up assurance and the web session,
/// neither of which a plain `refresh_token` grant (``AulaTokenRefresher``)
/// renews. See ``AulaFormWalker/reauthorize`` for the mechanics and
/// `DefaultAulaProvider/reauthorizedSession(_:)` for where this is called.
///
/// Abstracted so ``DefaultAulaProvider`` can exercise its retry logic against
/// a fake instead of the live broker.
protocol AulaReauthorizer: Sendable {
    func reauthorize(brokerCookies: [HTTPCookie], userAgent: String?) async throws
        -> AulaReauthResult
}

/// Production implementation: fresh PKCE material against a fresh authorize
/// URL, walked headlessly via ``AulaFormWalker/reauthorize``.
struct DefaultAulaReauthorizer: AulaReauthorizer {
    func reauthorize(brokerCookies: [HTTPCookie], userAgent: String?) async throws
        -> AulaReauthResult
    {
        let config = AulaOAuth.config()
        let codeVerifier = PKCEUtilities.generateCodeVerifier()
        let codeChallenge = PKCEUtilities.generateCodeChallenge(from: codeVerifier)
        let state = PKCEUtilities.generateState()
        let authorizationURL = try PKCEOAuthFlow.buildAuthorizationURL(
            config: config,
            codeChallenge: codeChallenge,
            state: state
        )

        let result = try await AulaFormWalker.reauthorize(
            authorizationURL: authorizationURL,
            brokerCookies: brokerCookies,
            expectedState: state,
            codeVerifier: codeVerifier,
            redirectHost: URL(string: config.redirectURI)?.host ?? AulaOAuth.redirectHost,
            config: config,
            userAgent: userAgent,
            log: { message in AppLogger.debug("\(private: message)", category: .network) }
        )
        return AulaReauthResult(tokens: result.tokens, cookies: result.cookies)
    }
}
