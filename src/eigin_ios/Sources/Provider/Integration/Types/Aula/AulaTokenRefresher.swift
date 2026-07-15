import Foundation

/// Renews an Aula access token from a refresh token. This keeps the base
/// token alive past its ~1 hour expiry, but does not restore MitID step-up
/// assurance or the web session — those decay separately and need a silent
/// re-authorize instead.
protocol AulaTokenRefresher: Sendable {
    func refresh(refreshToken: String) async throws -> TokenResponse
}

/// Production implementation: a plain `refresh_token` grant against Aula's OIDC
/// token endpoint via the shared ``PKCEOAuthFlow``.
struct DefaultAulaTokenRefresher: AulaTokenRefresher {
    func refresh(refreshToken: String) async throws -> TokenResponse {
        try await PKCEOAuthFlow.refresh(
            refreshToken: refreshToken,
            config: AulaOAuth.config()
        )
    }
}
