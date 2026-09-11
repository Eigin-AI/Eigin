import Foundation
import Observation

/// The reporting seam providers use to say their connection can no longer
/// authenticate — implemented by ``IntegrationHealthMonitor`` and faked in
/// tests. Kept separate so providers depend on the one-method behavior, not
/// the @MainActor observable that backs the UI.
protocol IntegrationHealthReporter: Sendable {
    /// Records that `integrationID` needs an interactive reconnect. Safe to
    /// call from any actor — implementations hop to their own isolation.
    nonisolated func markNeedsReconnect(_ integrationID: UUID)
}

/// Tracks which connected integrations have lost the ability to sign in
/// automatically (dead refresh token, expired session, rotated credentials) so
/// the Connections list and detail screen can nudge the user to reconnect.
///
/// Two sources feed ``needsReconnect(_:oauthService:)``:
///
/// - a runtime flag providers set at their sure auth-death sites (any auth
///   kind — cleared only by a successful reconnect), and
/// - for OAuth types, the keychain: ``DefaultIntegrationOAuthService`` clears
///   tokens when a refresh fails, and an absent token persists across
///   restarts, so a dead Google/Microsoft connection stays flagged even after
///   a relaunch. Aula/IMAP have no equivalent durable signal — they simply
///   re-flag on the next failed use.
@MainActor
@Observable
final class IntegrationHealthMonitor: IntegrationHealthReporter, IntegrationHealthMonitoring {
    static let shared = IntegrationHealthMonitor()

    /// Integration ids reported as needing a reconnect by their providers.
    private(set) var flagged: Set<UUID> = []

    init() {}

    nonisolated func markNeedsReconnect(_ integrationID: UUID) {
        Task { @MainActor in
            self.flagged.insert(integrationID)
        }
    }

    /// Clears the runtime flag after a successful reconnect.
    func clearNeedsReconnect(_ integrationID: UUID) {
        flagged.remove(integrationID)
    }

    /// Whether `integration` needs a reconnect: it was flagged at runtime, or
    /// (OAuth types only) no access token survives in the keychain — the
    /// durable post-refresh-failure state.
    func needsReconnect(
        _ integration: Integration,
        oauthService: any IntegrationOAuthService
    ) -> Bool {
        if flagged.contains(integration.id) { return true }
        guard let type = BundledIntegrationType.type(forID: integration.typeID),
              case .oauth = type.authKind
        else { return false }
        return !oauthService.hasStoredTokens(for: integration.id)
    }
}
