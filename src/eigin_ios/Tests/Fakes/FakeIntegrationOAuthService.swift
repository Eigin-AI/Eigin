@testable import Eigin
import Foundation

/// Always returns a fixed token — for testing integration backends
/// (e.g. ``GmailEmailProvider``) without exercising the OAuth flow itself.
final class FakeIntegrationOAuthService: IntegrationOAuthService, @unchecked Sendable {
    var token: String? = "fake-access-token"
    var scopes: Set<String> = []
    private(set) var clearedIDs: [UUID] = []
    private var authorizedIDList: [UUID] = []
    private let lock = NSLock()

    func authorize(config: PKCEOAuthConfig, integrationID: UUID) async throws -> String {
        lock.withLock { authorizedIDList.append(integrationID) }
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

    func hasStoredTokens(for integrationID: UUID) -> Bool {
        token != nil
    }

    /// The ids `authorize` was called with, in order.
    var authorizedIDs: [UUID] {
        lock.withLock { authorizedIDList }
    }
}
