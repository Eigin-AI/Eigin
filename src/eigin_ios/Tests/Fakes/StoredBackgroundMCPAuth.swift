@testable import Eigin
import Foundation
import Testing

struct StoredBackgroundMCPAuth: MCPOAuthService {
    func discoverOAuth(for serverURL: URL) async throws -> OAuthConfiguration? {
        Issue.record("Initiative must not discover authorization")
        return nil
    }

    func authorize(config: OAuthConfiguration, serverID: UUID) async throws -> String {
        Issue.record("Initiative must not open authorization UI")
        throw MCPServerConnection.ConnectionError.authExpired
    }

    func validToken(for serverID: UUID) async throws -> String? {
        "stored-token"
    }

    func clearTokens(for serverID: UUID) {}
}
