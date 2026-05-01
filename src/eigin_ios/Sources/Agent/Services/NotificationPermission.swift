import UserNotifications

/// Helper for requesting local notification permission.
enum NotificationPermission {
    /// Requests notification authorization if not yet determined.
    /// Returns `true` if notifications are authorized.
    static func requestIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional:
            return true
        case .notDetermined:
            return await (try? center.requestAuthorization(options: [.alert, .sound, .badge])) ??
                false
        case .denied, .ephemeral:
            return false
        @unknown default:
            return false
        }
    }
}
