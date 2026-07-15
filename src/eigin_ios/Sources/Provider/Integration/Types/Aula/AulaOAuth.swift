import Foundation

/// Aula's known OAuth/OIDC endpoints for the `aula` capability — Aula's own
/// login endpoints (SimpleSAMLphp OIDC module), not a client we register.
/// `clientID` is Aula's mobile-app client id (see ``AppKeys/aulaOAuthClientID``).
/// Stable enough to live as code constants, mirroring ``GoogleOAuth``. See
/// `docs/src/integrations/aula.md` for the login flow this feeds.
enum AulaOAuth {
    /// Where Aula redirects after a successful login. Not a page we host — the
    /// WKWebView cancels the load the moment it sees this prefix and reads the
    /// `code`/`state` off the URL.
    static let redirectURI = "https://app-private.aula.dk"

    /// `redirectURI`'s host, shared so callers that need a fallback (when
    /// parsing `redirectURI` as a `URL` fails) all fall back to the same
    /// value rather than each hardcoding their own copy.
    static let redirectHost = "app-private.aula.dk"

    static let authorizationEndpoint =
        URL(string: "https://login.aula.dk/simplesaml/module.php/oidc/authorize.php")!
    static let tokenEndpoint =
        URL(string: "https://login.aula.dk/simplesaml/module.php/oidc/token.php")!
    static let scopes = ["aula-sensitive"]

    static func config() -> PKCEOAuthConfig {
        PKCEOAuthConfig(
            authorizationEndpoint: authorizationEndpoint,
            tokenEndpoint: tokenEndpoint,
            clientID: AppKeys.aulaOAuthClientID,
            scopes: scopes,
            redirectURI: redirectURI
        )
    }
}
