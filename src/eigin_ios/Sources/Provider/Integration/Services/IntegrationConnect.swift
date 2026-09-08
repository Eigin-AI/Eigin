import Foundation

/// Shared completion step for OAuth-backed integration types, used by both
/// connecting a new account (``ConnectIntegrationSheet``) and reconnecting an existing
/// one (``IntegrationScreen``) so the two can't drift apart.
enum IntegrationConnect {
    /// The connect outcome an ``Integration`` row needs: the label to show and
    /// which of the type's capabilities the grant actually covers.
    struct OAuthResult: Equatable {
        let accountLabel: String
        let grantedCapabilities: Set<Capability>
    }

    /// Runs the full authorization flow for `type` and stores its tokens under
    /// `integrationID` — connecting passes a freshly-minted id, reconnecting
    /// passes the existing integration's so the keychain namespace (and every
    /// reference to it) survives. `labelFallback` is used when the type can't
    /// resolve a better account label from the just-issued token.
    static func authorizeOAuth(
        oauthService: any IntegrationOAuthService,
        type: IntegrationType,
        config: PKCEOAuthConfig,
        integrationID: UUID,
        labelFallback: String
    ) async throws -> OAuthResult {
        // Client id comes from a build-time secret (see `.env` / project.yml) —
        // if it's missing, authorize() would launch a browser session that can
        // never complete, which reads to the user as a silent hang.
        guard !config.clientID.isEmpty else {
            throw IntegrationOAuthError.notConfigured(type.displayName)
        }

        let accessToken = try await oauthService.authorize(
            config: config,
            integrationID: integrationID
        )
        let accountLabel = await type.accountLabel(accessToken) ?? labelFallback

        // Google's consent screen lets the user deny individual scopes, so
        // don't assume every requested capability was granted.
        let grantedScopes = oauthService.grantedScopes(for: integrationID)
        let grantedCapabilities = type.grantedCapabilities(fromGrantedScopes: grantedScopes)

        return OAuthResult(
            accountLabel: accountLabel,
            grantedCapabilities: grantedCapabilities
        )
    }
}
