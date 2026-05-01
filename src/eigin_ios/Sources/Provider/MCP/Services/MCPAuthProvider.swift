import Foundation
import os

/// Provides authentication tokens for MCP server requests.
protocol MCPAuthProvider: Sendable {
    /// Returns the current token to inject as a Bearer header, or nil for no auth.
    /// Refreshes automatically if the stored token is expired.
    func currentToken() async throws -> String?
}

/// No authentication — for MCP servers that require no credentials.
struct NoAuthProvider: MCPAuthProvider {
    func currentToken() async throws -> String? {
        nil
    }
}

/// OAuth 2.1 authentication — delegates token management to ``MCPOAuthService``.
struct OAuthAuthProvider: MCPAuthProvider {
    private let oauthService: any MCPOAuthService
    private let serverID: UUID

    init(oauthService: any MCPOAuthService, serverID: UUID) {
        self.oauthService = oauthService
        self.serverID = serverID
    }

    func currentToken() async throws -> String? {
        try await oauthService.validToken(for: serverID)
    }
}

/// Thread-safe cache for the current access token, readable from synchronous contexts.
final class TokenCache: Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: String?.none)

    var current: String? {
        get { lock.withLock { $0 } }
        set { lock.withLock { $0 = newValue } }
    }
}
