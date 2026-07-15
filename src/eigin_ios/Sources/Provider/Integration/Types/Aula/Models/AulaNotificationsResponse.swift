import Foundation

/// Response shape for `notifications.getNotificationsForActiveProfile`.
struct AulaNotificationsResponse: Decodable {
    let data: [Notification]

    struct Notification: Decodable {
        let message: String?
        let triggered: String?
    }
}
