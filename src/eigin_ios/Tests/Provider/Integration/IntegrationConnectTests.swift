@testable import Eigin
import Foundation
import Testing

/// Verifies the shared OAuth connect step used by both adding and
/// reconnecting an integration: label + capability derivation from granted
/// scopes, and the failure modes that must surface before a browser session
/// would launch.
@Suite("IntegrationConnect")
struct IntegrationConnectTests {
    private func makeConfig(clientID: String = "client-123") -> PKCEOAuthConfig {
        PKCEOAuthConfig(
            authorizationEndpoint: URL(string: "https://example.com/authorize")!,
            tokenEndpoint: URL(string: "https://example.com/token")!,
            clientID: clientID
        )
    }

    @Test func authorizeBuildsLabelAndCapabilityFromGrantedScopes() async throws {
        let oauth = FakeIntegrationOAuthService()
        oauth.scopes = [
            "https://www.googleapis.com/auth/gmail.readonly",
            "https://www.googleapis.com/auth/gmail.send",
        ]
        let type = IntegrationType(
            id: "test",
            displayName: "Test",
            description: "",
            systemImage: "envelope",
            providedCapabilities: [.email],
            category: .email,
            authKind: .oauth(configFactory: { PKCEOAuthConfig(
                authorizationEndpoint: URL(string: "https://example.com/authorize")!,
                tokenEndpoint: URL(string: "https://example.com/token")!,
                clientID: "client-123"
            ) }),
            requiredScopes: [
                .email: ["https://www.googleapis.com/auth/gmail.readonly"],
            ],
            toolCapabilities: [],
            makeTools: { _, _, _ in [] },
            accountLabel: { _ in "resolved@example.com" }
        )

        let result = try await IntegrationConnect.authorizeOAuth(
            oauthService: oauth,
            type: type,
            config: makeConfig(),
            integrationID: UUID(),
            labelFallback: "fallback"
        )

        #expect(result.accountLabel == "resolved@example.com")
        #expect(result.grantedCapabilities == [.email])
    }

    @Test func fallsBackToLabelWhenAccountLabelFails() async throws {
        let oauth = FakeIntegrationOAuthService()
        oauth.scopes = []
        let type = BundledIntegrationType.google
        // Google's accountLabel closure would hit the network — use a local
        // type with the default (nil) label closure instead.
        let local = IntegrationType(
            id: "test",
            displayName: "Test",
            description: "",
            systemImage: "envelope",
            providedCapabilities: [],
            category: .email,
            authKind: .oauth(configFactory: { PKCEOAuthConfig(
                authorizationEndpoint: URL(string: "https://example.com/authorize")!,
                tokenEndpoint: URL(string: "https://example.com/token")!,
                clientID: "client-123"
            ) }),
            toolCapabilities: [],
            makeTools: { _, _, _ in [] }
        )

        let result = try await IntegrationConnect.authorizeOAuth(
            oauthService: oauth,
            type: local,
            config: makeConfig(),
            integrationID: UUID(),
            labelFallback: "previous-label"
        )

        #expect(result.accountLabel == "previous-label")
    }

    @Test func emptyClientIDThrowsNotConfigured() async {
        let oauth = FakeIntegrationOAuthService()

        await #expect(throws: IntegrationOAuthError.notConfigured("Google")) {
            _ = try await IntegrationConnect.authorizeOAuth(
                oauthService: oauth,
                type: BundledIntegrationType.google,
                config: makeConfig(clientID: ""),
                integrationID: UUID(),
                labelFallback: "fallback"
            )
        }
    }

    @Test func usesTheGivenIntegrationID() async throws {
        let oauth = FakeIntegrationOAuthService()
        let id = UUID()
        let type = IntegrationType(
            id: "test",
            displayName: "Test",
            description: "",
            systemImage: "envelope",
            providedCapabilities: [],
            category: .email,
            authKind: .oauth(configFactory: { PKCEOAuthConfig(
                authorizationEndpoint: URL(string: "https://example.com/authorize")!,
                tokenEndpoint: URL(string: "https://example.com/token")!,
                clientID: "client-123"
            ) }),
            toolCapabilities: [],
            makeTools: { _, _, _ in [] }
        )

        _ = try await IntegrationConnect.authorizeOAuth(
            oauthService: oauth,
            type: type,
            config: makeConfig(),
            integrationID: id,
            labelFallback: "fallback"
        )

        // The shared flow never mints its own id — connecting passes a fresh
        // one, reconnecting passes the existing integration's.
        #expect(oauth.authorizedIDs == [id])
    }
}
