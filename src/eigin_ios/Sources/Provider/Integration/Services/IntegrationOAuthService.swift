import Foundation

/// Manages OAuth tokens for a connected ``Integration``.
///
/// Unlike ``MCPOAuthService``, there is no discovery step — endpoints are
/// pre-configured per ``IntegrationType`` (e.g. Google's known endpoints).
/// Built on the same ``PKCEOAuthFlow`` mechanics as MCP, with its own
/// keychain namespace (`integrationKey`) keyed by ``Integration/id``.
protocol IntegrationOAuthService: Sendable {
    /// Full PKCE flow: browser auth → code exchange → store tokens in Keychain.
    func authorize(config: PKCEOAuthConfig, integrationID: UUID) async throws -> String
    /// Reads the access token, refreshing if expired. Returns nil if none stored.
    func validToken(config: PKCEOAuthConfig, integrationID: UUID) async throws -> String?
    /// The OAuth scopes actually granted by the user at authorization time —
    /// may be a subset of what was requested (e.g. the user denied one
    /// scope in Google's consent screen). Empty if nothing was recorded.
    func grantedScopes(for integrationID: UUID) -> Set<String>
    /// Deletes all stored OAuth tokens for an integration.
    func clearTokens(for integrationID: UUID)
    /// Whether tokens exist under this id — false after a failed refresh
    /// cleared them, which is the durable "needs reconnect" signal for OAuth
    /// types (it survives restarts, unlike a provider's in-memory flag).
    func hasStoredTokens(for integrationID: UUID) -> Bool
}

final class DefaultIntegrationOAuthService: IntegrationOAuthService, @unchecked Sendable {
    private let keychainService: any KeychainService
    private let urlSession: URLSession

    /// Keychain storage suffixes for integration OAuth credentials — named
    /// constants so the four strings live in one place instead of being
    /// retyped at every read/write call site.
    private enum Suffix {
        static let accessToken = "access_token"
        static let refreshToken = "refresh_token"
        static let tokenExpiry = "token_expiry"
        static let scope = "scope"
        static let all = [accessToken, refreshToken, tokenExpiry, scope]
    }

    init(keychainService: any KeychainService, urlSession: URLSession = .shared) {
        self.keychainService = keychainService
        self.urlSession = urlSession
    }

    func authorize(config: PKCEOAuthConfig, integrationID: UUID) async throws -> String {
        let tokenResponse: TokenResponse
        do {
            tokenResponse = try await PKCEOAuthFlow.authorize(
                config: config,
                urlSession: urlSession
            )
        } catch PKCEOAuthFlow.FlowError.userCancelled {
            throw IntegrationOAuthError.userCancelled
        } catch let error as PKCEOAuthFlow.FlowError {
            throw IntegrationOAuthError.authorizationFailed(error.localizedDescription)
        }
        storeTokens(tokenResponse, integrationID: integrationID)
        return tokenResponse.accessToken
    }

    func validToken(config: PKCEOAuthConfig, integrationID: UUID) async throws -> String? {
        guard let accessToken = readKeychain(
            integrationID: integrationID,
            suffix: Suffix.accessToken
        )
        else {
            return nil
        }

        if let expiryString = readKeychain(
            integrationID: integrationID,
            suffix: Suffix.tokenExpiry
        ),
            let expiry = ISO8601DateFormatter().date(from: expiryString)
        {
            if expiry.timeIntervalSinceNow > 60 {
                return accessToken
            }
        } else {
            // No expiry stored — assume the token is valid (mirrors MCPOAuthService).
            return accessToken
        }

        guard let refreshToken = readKeychain(
            integrationID: integrationID,
            suffix: Suffix.refreshToken
        )
        else {
            clearTokens(for: integrationID)
            return nil
        }

        let tokenResponse: TokenResponse
        do {
            tokenResponse = try await PKCEOAuthFlow.refresh(
                refreshToken: refreshToken,
                config: config,
                urlSession: urlSession
            )
        } catch {
            clearTokens(for: integrationID)
            return nil
        }

        storeTokens(tokenResponse, integrationID: integrationID)
        return tokenResponse.accessToken
    }

    func grantedScopes(for integrationID: UUID) -> Set<String> {
        guard let scope = readKeychain(integrationID: integrationID, suffix: Suffix.scope) else {
            return []
        }
        return Set(scope.split(separator: " ").map(String.init))
    }

    func clearTokens(for integrationID: UUID) {
        for suffix in Suffix.all {
            keychainService.delete(key: keychainService.integrationKey(
                for: integrationID,
                suffix: suffix
            ))
        }
    }

    func hasStoredTokens(for integrationID: UUID) -> Bool {
        readKeychain(integrationID: integrationID, suffix: Suffix.accessToken) != nil
    }

    // MARK: - Private

    private func storeTokens(_ response: TokenResponse, integrationID: UUID) {
        saveKeychain(
            integrationID: integrationID,
            suffix: Suffix.accessToken,
            value: response.accessToken
        )
        if let refreshToken = response.refreshToken {
            saveKeychain(
                integrationID: integrationID,
                suffix: Suffix.refreshToken,
                value: refreshToken
            )
        }
        if let expiresIn = response.expiresIn {
            let expiry = Date.now.addingTimeInterval(TimeInterval(expiresIn))
            saveKeychain(
                integrationID: integrationID,
                suffix: Suffix.tokenExpiry,
                value: ISO8601DateFormatter().string(from: expiry)
            )
        }
        if let scope = response.scope {
            saveKeychain(integrationID: integrationID, suffix: Suffix.scope, value: scope)
        }
    }

    private func readKeychain(integrationID: UUID, suffix: String) -> String? {
        keychainService.read(key: keychainService.integrationKey(
            for: integrationID,
            suffix: suffix
        ))
    }

    private func saveKeychain(integrationID: UUID, suffix: String, value: String) {
        keychainService.save(
            key: keychainService.integrationKey(for: integrationID, suffix: suffix),
            value: value
        )
    }
}

/// User-facing: surfaced directly in ``ConnectIntegrationSheet``'s error UI, so
/// unlike ``EmailProviderError`` these are localized.
enum IntegrationOAuthError: Error, LocalizedError, Equatable {
    case userCancelled
    case notConfigured(String)
    case authorizationFailed(String)

    var errorDescription: String? {
        switch self {
        case .userCancelled:
            Localized.Errors.Authentication.cancelled
        case .notConfigured(let name):
            "\(name) isn't configured in this build — its OAuth client id is missing."
        case .authorizationFailed(let reason):
            Localized.Errors.Authorization.failedWithReason(reason)
        }
    }
}
