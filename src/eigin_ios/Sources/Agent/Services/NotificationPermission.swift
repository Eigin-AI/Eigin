import UserNotifications

/// Access to system notification authorization.
protocol NotificationAuthorizationAccess: Sendable {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization() async throws -> Bool
}

struct SystemNotificationAuthorization: NotificationAuthorizationAccess {
    func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func requestAuthorization() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [
            .alert,
            .sound,
            .badge,
        ])
    }
}

/// Helper for requesting local notification permission.
enum NotificationPermission {
    /// Requests undetermined authorization only when the caller can prompt the user.
    static func requestIfNeeded(
        canPromptUser: Bool = true,
        authorization: any NotificationAuthorizationAccess = SystemNotificationAuthorization()
    ) async -> Bool {
        switch await authorization.authorizationStatus() {
        case .authorized, .provisional:
            return true
        case .notDetermined:
            guard canPromptUser else { return false }
            return await (try? authorization.requestAuthorization()) ?? false
        case .denied, .ephemeral:
            return false
        @unknown default:
            return false
        }
    }
}
