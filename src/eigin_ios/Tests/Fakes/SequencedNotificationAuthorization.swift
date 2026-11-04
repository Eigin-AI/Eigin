@testable import Eigin
import UserNotifications

actor SequencedNotificationAuthorization: NotificationAuthorizationAccess {
    private var statuses: [UNAuthorizationStatus]

    init(_ statuses: [UNAuthorizationStatus]) {
        self.statuses = statuses
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        if statuses.count > 1 { return statuses.removeFirst() }
        return statuses.first ?? .denied
    }

    func requestAuthorization() async throws -> Bool {
        true
    }
}
