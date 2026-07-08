@testable import Eigin
import Foundation

/// Always returns a fixed token — for testing integration backends
/// (e.g. ``GmailEmailProvider``) without exercising the OAuth flow itself.
final class FakeIntegrationOAuthService: IntegrationOAuthService, @unchecked Sendable {
    var token: String? = "fake-access-token"
    var scopes: Set<String> = []
    private(set) var clearedIDs: [UUID] = []

    func authorize(config: PKCEOAuthConfig, integrationID: UUID) async throws -> String {
        guard let token else { throw IntegrationOAuthError.authorizationFailed("no token") }
        return token
    }

    func validToken(config: PKCEOAuthConfig, integrationID: UUID) async throws -> String? {
        token
    }

    func grantedScopes(for integrationID: UUID) -> Set<String> {
        scopes
    }

    func clearTokens(for integrationID: UUID) {
        clearedIDs.append(integrationID)
        token = nil
    }
}
