import Foundation

/// Configuration for a single PKCE authorization-code flow.
///
/// Shared by ``MCPOAuthService`` (server-discovered endpoints) and
/// ``IntegrationOAuthService`` (pre-configured endpoints, e.g. Google). The
/// two callers differ in how endpoints are obtained and in a couple of
/// provider-specific request params (MCP's `resource` indicator) — both of
/// which are expressed here as data, not behavior.
struct PKCEOAuthConfig: Sendable {
    let authorizationEndpoint: URL
    let tokenEndpoint: URL
    let clientID: String
    let clientSecret: String?
    let scopes: [String]
    /// Where the authorization server redirects after consent. Defaults to the
    /// HTTPS passthrough (``PKCEOAuthFlow/defaultRedirectURI``), which works even
    /// for providers that reject arbitrary custom URL schemes.
    let redirectURI: String
    /// Extra query params merged into the authorization request.
    let extraAuthorizationParams: [String: String]
    /// Extra form params merged into token exchange and refresh requests.
    let extraTokenParams: [String: String]

    init(
        authorizationEndpoint: URL,
        tokenEndpoint: URL,
        clientID: String,
        clientSecret: String? = nil,
        scopes: [String] = [],
        redirectURI: String = PKCEOAuthFlow.defaultRedirectURI,
        extraAuthorizationParams: [String: String] = [:],
        extraTokenParams: [String: String] = [:]
    ) {
        self.authorizationEndpoint = authorizationEndpoint
        self.tokenEndpoint = tokenEndpoint
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.scopes = scopes
        self.redirectURI = redirectURI
        self.extraAuthorizationParams = extraAuthorizationParams
        self.extraTokenParams = extraTokenParams
    }
}
