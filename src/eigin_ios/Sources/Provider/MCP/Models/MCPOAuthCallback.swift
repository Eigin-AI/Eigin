import Foundation

/// Redirect registered with the server and the scheme completing browser authentication.
struct MCPOAuthCallback: Sendable {
    let redirectURI: String
    let callbackScheme: String

    static let app = MCPOAuthCallback(
        redirectURI: "ai.eigin://oauth/callback", callbackScheme: "ai.eigin"
    )

    static let httpsRedirect = MCPOAuthCallback(
        redirectURI: PKCEOAuthFlow.defaultRedirectURI, callbackScheme: "eigin"
    )

    /// Uses the known host's preset callback for the entered endpoint.
    static func forEndpoint(_ endpoint: URL) -> MCPOAuthCallback {
        guard let components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https",
              let host = components.host?.lowercased(),
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil
        else { return .app }
        let preset = MCPPreset.all.first {
            $0.endpoint.scheme?.lowercased() == components.scheme?.lowercased()
                && $0.endpoint.host?.lowercased() == host
                && ($0.endpoint.port ?? 443) == (components.port ?? 443)
        }
        return preset?.oauthCallback ?? .app
    }
}
