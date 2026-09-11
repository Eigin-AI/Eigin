import Observation
import SwiftUI

/// The view-facing surface of ``IntegrationHealthMonitor``: which connections
/// have lost automatic sign-in and need an interactive reconnect.
///
/// Tests and screenshot scenes register their own monitor in the container
/// (`integrationHealthMonitor`) so screens can render reconnect state without
/// real credentials or OAuth backends.
@MainActor
protocol IntegrationHealthMonitoring: Observable {
    /// Whether `integration` needs an interactive reconnect.
    func needsReconnect(
        _ integration: Integration,
        oauthService: any IntegrationOAuthService
    ) -> Bool

    /// Clears the flag after a successful reconnect.
    func clearNeedsReconnect(_ integrationID: UUID)
}
