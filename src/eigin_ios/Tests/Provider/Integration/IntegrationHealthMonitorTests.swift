@testable import Eigin
import Foundation
import Testing

/// Verifies the "needs reconnect" signal: runtime flags plus the durable OAuth
/// keychain derivation, and nothing for other auth kinds.
@MainActor
@Suite("IntegrationHealthMonitor")
struct IntegrationHealthMonitorTests {
    @Test func runtimeFlagMarksAndClears() async {
        let monitor = IntegrationHealthMonitor()
        let id = UUID()

        monitor.markNeedsReconnect(id)
        #expect(await flagLands(monitor, id: id) == true)

        monitor.clearNeedsReconnect(id)
        #expect(monitor.flagged.isEmpty)
    }

    @Test func flaggingADifferentIntegrationDoesNotFlagThisOne() {
        let monitor = IntegrationHealthMonitor()
        let integration = integration(typeID: "imap")

        monitor.markNeedsReconnect(UUID())

        #expect(monitor.needsReconnect(integration, oauthService: FakeIntegrationOAuthService()) ==
            false)
    }

    @Test func clearedFlagStaysClearedForOAuthWithTokens() {
        let monitor = IntegrationHealthMonitor()
        let integration = integration(typeID: "google")
        let oauth = FakeIntegrationOAuthService()
        oauth.token = nil

        monitor.markNeedsReconnect(integration.id)
        monitor.clearNeedsReconnect(integration.id)

        // The runtime flag cleared, but the durable keychain derivation still
        // says a dead token is dead — clearing is what the *reconnect success*
        // path does, after authorize() has stored new tokens. With the fake
        // reporting no stored token, a clear alone can't bury that state.
        oauth.token = "restored-token"
        #expect(monitor.needsReconnect(integration, oauthService: oauth) == false)
    }

    @Test func oauthWithoutStoredTokensNeedsReconnectAcrossRestarts() {
        let monitor = IntegrationHealthMonitor()
        let integration = integration(typeID: "google")

        // No runtime flag — this is the durable derivation that recovers the
        // state after a relaunch (tokens were cleared by a failed refresh).
        let oauth = FakeIntegrationOAuthService()
        oauth.token = nil

        #expect(monitor.needsReconnect(integration, oauthService: oauth) == true)
    }

    @Test func oauthWithStoredTokensDoesNotNeedReconnect() {
        let monitor = IntegrationHealthMonitor()
        let integration = integration(typeID: "microsoft")

        let oauth = FakeIntegrationOAuthService()
        oauth.token = "stored-token"

        #expect(monitor.needsReconnect(integration, oauthService: oauth) == false)
    }

    @Test func nonOAuthKindsNeverDeriveFromMissingTokens() {
        let monitor = IntegrationHealthMonitor()
        let oauth = FakeIntegrationOAuthService()
        oauth.token = nil

        // Aula (.webSession) and IMAP (.imap) have no durable signal — only a
        // runtime flag can mark them.
        for typeID in ["aula", "imap"] {
            #expect(monitor.needsReconnect(integration(typeID: typeID), oauthService: oauth) ==
                false)
        }
    }

    private func integration(typeID: String) -> Integration {
        Integration(
            typeID: typeID,
            accountLabel: "Test",
            grantedCapabilities: []
        )
    }

    /// markNeedsReconnect hops to the main actor — waits for that hop to land
    /// before the assert reads the flag.
    private func flagLands(
        _ monitor: IntegrationHealthMonitor,
        id: UUID
    ) async -> Bool {
        for _ in 0 ..< 100 where !monitor.flagged.contains(id) {
            await Task.yield()
        }
        return monitor.flagged.contains(id)
    }
}
