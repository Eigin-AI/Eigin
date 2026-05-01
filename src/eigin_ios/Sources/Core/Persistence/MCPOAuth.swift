import Foundation

// MARK: - Discovery Metadata

struct ProtectedResourceMetadata: Codable {
    let resource: String?
    let authorizationServers: [String]?

    enum CodingKeys: String, CodingKey {
        case resource
        case authorizationServers = "authorization_servers"
    }
}

struct AuthorizationServerMetadata: Codable {
    let issuer: String?
    let authorizationEndpoint: String
    let tokenEndpoint: String
    let registrationEndpoint: String?
    let scopesSupported: [String]?
    let codeChallengeMethodsSupported: [String]?

    enum CodingKeys: String, CodingKey {
        case issuer
        case authorizationEndpoint = "authorization_endpoint"
        case tokenEndpoint = "token_endpoint"
        case registrationEndpoint = "registration_endpoint"
        case scopesSupported = "scopes_supported"
        case codeChallengeMethodsSupported = "code_challenge_methods_supported"
    }
}

// MARK: - Registration & Tokens

struct ClientRegistrationResponse: Codable {
    let clientId: String
    let clientSecret: String?

    enum CodingKeys: String, CodingKey {
        case clientId = "client_id"
        case clientSecret = "client_secret"
    }
}

struct TokenResponse: Codable {
    let accessToken: String
    let tokenType: String
    let expiresIn: Int?
    let refreshToken: String?
    let scope: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case scope
    }
}

// MARK: - Configuration

/// Resolved OAuth configuration for an MCP server, produced by discovery.
struct OAuthConfiguration {
    let resourceURL: URL
    let authorizationEndpoint: URL
    let tokenEndpoint: URL
    /// Nil when the server doesn't support dynamic registration and the user
    /// must provide credentials manually.
    let clientID: String?
    let clientSecret: String?
    let scopes: [String]?

    /// Whether the user needs to supply client credentials (no dynamic registration).
    var needsClientCredentials: Bool {
        clientID == nil
    }

    /// Returns a copy with the given client credentials filled in.
    func withClientCredentials(clientID: String, clientSecret: String?) -> OAuthConfiguration {
        OAuthConfiguration(
            resourceURL: resourceURL,
            authorizationEndpoint: authorizationEndpoint,
            tokenEndpoint: tokenEndpoint,
            clientID: clientID,
            clientSecret: clientSecret,
            scopes: scopes
        )
    }
}

// MARK: - Errors

enum MCPOAuthError: Error, LocalizedError {
    case serverNotProtected
    case metadataDiscoveryFailed(String)
    case noAuthorizationServers
    case authorizationFailed(String)
    case tokenRefreshFailed(String)
    case registrationFailed(String)
    case userCancelled

    var errorDescription: String? {
        switch self {
        case .serverNotProtected:
            "Server does not require authentication"
        case .metadataDiscoveryFailed(let reason):
            "Failed to discover OAuth metadata: \(reason)"
        case .noAuthorizationServers:
            "No authorization servers found in resource metadata"
        case .authorizationFailed(let reason):
            "Authorization failed: \(reason)"
        case .tokenRefreshFailed(let reason):
            "Token refresh failed: \(reason)"
        case .registrationFailed(let reason):
            "Client registration failed: \(reason)"
        case .userCancelled:
            "Authorization was cancelled"
        }
    }
}
