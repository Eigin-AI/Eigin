import Foundation

/// Google's known OAuth endpoints and scopes for the Gmail email capability.
///
/// No discovery step is needed (unlike MCP) — Google's endpoints are stable
/// and well documented. Uses the shared HTTPS passthrough redirect
/// (`PKCEOAuthFlow.defaultRedirectURI`) rather than a direct custom scheme,
/// since Google's public iOS client type doesn't accept arbitrary schemes.
enum GoogleOAuth {
    static func config() -> PKCEOAuthConfig {
        PKCEOAuthConfig(
            authorizationEndpoint: URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
            tokenEndpoint: URL(string: "https://oauth2.googleapis.com/token")!,
            clientID: AppKeys.googleOAuthClientID,
            scopes: [
                "https://www.googleapis.com/auth/gmail.readonly",
                "https://www.googleapis.com/auth/gmail.send",
                "https://www.googleapis.com/auth/userinfo.email",
            ],
            redirectURI: redirectURI(clientID: AppKeys.googleOAuthClientID),
            extraAuthorizationParams: [
                "access_type": "offline",
                "prompt": "consent",
            ]
        )
    }

    /// Google's iOS OAuth client type doesn't accept a configurable redirect
    /// URI — it's implicitly fixed to the reversed client ID as a custom
    /// scheme (the same convention Google's own Sign-In SDK uses), so we have
    /// to construct it rather than use the shared HTTPS passthrough.
    static func redirectURI(clientID: String) -> String {
        let reversed = clientID.split(separator: ".").reversed().joined(separator: ".")
        return "\(reversed):/oauth2redirect"
    }
}
