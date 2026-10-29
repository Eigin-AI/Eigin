import Foundation

/// Endpoints and client identity for Infercom sign-in (issue #337).
///
/// Infercom's flow is two-legged: a standard PKCE authorization-code login at
/// `auth.infercom.ai`, then an RFC 8693 token exchange at `cloud.infercom.ai`
/// that trades the **login access token** (not the ID token) for the API
/// Bearer token used against `api.infercom.ai`.
enum InfercomSignInConstants {
    /// Public client — PKCE S256, no secret.
    static let clientID = "tpc_sQ5yecK6rYJte4ssz4Eqoc"
    static let authorizationEndpoint = URL(string: "https://auth.infercom.ai/authorize")!
    static let tokenEndpoint = URL(string: "https://auth.infercom.ai/oauth/token")!
    /// RFC 8693 exchange endpoint — a different server than the login.
    static let exchangeEndpoint = URL(string: "https://cloud.infercom.ai/oauth/token")!
    /// No third-party logout exists; sign-out revokes the refresh token here.
    static let revocationEndpoint = URL(string: "https://auth.infercom.ai/oauth/revoke")!
    static let apiBaseURL = "https://api.infercom.ai/v1"
    static let scopes = [
        "openid", "profile", "email", "sambastack.api.exchange", "offline_access",
    ]
    static let audience = "https://api.infercom.ai/"

    /// Shared PKCE config for the login leg. The redirect defaults to
    /// `PKCEOAuthFlow.defaultRedirectURI` (`auth.eigin.ai/callback/`), which
    /// passes through to the `eigin://` scheme the session intercepts.
    static var pkceConfig: PKCEOAuthConfig {
        PKCEOAuthConfig(
            authorizationEndpoint: authorizationEndpoint,
            tokenEndpoint: tokenEndpoint,
            clientID: clientID,
            scopes: scopes,
            extraAuthorizationParams: ["audience": audience]
        )
    }
}
