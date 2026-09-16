import SwiftData
import UserNotifications

// Ugly but needed for Swift6 compatibility: https://stackoverflow.com/questions/73750724/how-can-usernotificationcenter-didreceive-cause-a-crash-even-with-nothing-in
extension UNUserNotificationCenter: @unchecked @retroactive Sendable {}
extension UNNotificationResponse: @unchecked @retroactive Sendable {}
extension UNNotification: @unchecked @retroactive Sendable {}

@MainActor
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    let modelContainer: ModelContainer

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    /// Called when user taps a notification — signal pending navigation to the app.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo

        // A watch reply routes to the watch chat it came from.
        if let chatIDString = userInfo["chatID"] as? String,
           let chatID = UUID(uuidString: chatIDString)
        {
            AppLogger.info(
                "Notification tapped, chat: \(public: chatID)", category: .watch
            )
            PendingDestination.set(.chat(chatID))
            return
        }

        guard let requestIDString = userInfo["initiativeRequestID"] as? String,
              let requestID = UUID(uuidString: requestIDString)
        else {
            AppLogger.warning(
                "Notification tapped but missing initiativeRequestID",
                category: .backgroundPrompt
            )
            return
        }

        AppLogger.info(
            "Notification tapped, initiative request: \(public: requestID)",
            category: .backgroundPrompt
        )
        PendingDestination.set(.initiative(requestID))
    }

    /// Show notification banner even when app is in foreground.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
