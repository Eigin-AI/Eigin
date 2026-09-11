#if DEBUG || EIGIN_DEV
import Foundation
import Observation

/// Fake ``IntegrationHealthMonitoring`` for screenshots and tests: flagged
/// integrations can be seeded, so a scene can render the reconnect badge
/// without real credentials or keychain state.
@MainActor
@Observable
final class FakeIntegrationHealthMonitor: IntegrationHealthMonitoring {
    var flagged: Set<UUID> = []

    init() {}

    func needsReconnect(
        _ integration: Integration,
        oauthService: any IntegrationOAuthService
    ) -> Bool {
        flagged.contains(integration.id)
    }

    func clearNeedsReconnect(_ integrationID: UUID) {
        flagged.remove(integrationID)
    }
}
#endif
