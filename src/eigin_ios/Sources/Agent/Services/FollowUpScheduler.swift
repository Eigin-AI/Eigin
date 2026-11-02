import Foundation
import SwiftData
import UserNotifications

/// Adds local notification requests to the system notification center.
@MainActor
protocol LocalNotificationScheduling: Sendable {
    func add(_ request: UNNotificationRequest) async throws
}

extension UNUserNotificationCenter: LocalNotificationScheduling {}

/// Prepares system communication-notification presentation.
@MainActor
protocol CommunicationNotificationPreparing: Sendable {
    func prepare(
        _ content: UNMutableNotificationContent,
        agentName: String,
        agentEmoji: String?,
        agentID: UUID,
        conversationID: String
    ) async -> UNNotificationContent
}

struct SystemCommunicationNotificationPreparer: CommunicationNotificationPreparing {
    func prepare(
        _ content: UNMutableNotificationContent,
        agentName: String,
        agentEmoji: String?,
        agentID: UUID,
        conversationID: String
    ) async -> UNNotificationContent {
        await CommunicationNotificationContent.upgrade(
            content,
            agentName: agentName,
            agentEmoji: agentEmoji,
            agentID: agentID,
            conversationID: conversationID
        )
    }
}

/// Persists follow-up context and schedules prepared notifications.
@MainActor
protocol FollowUpScheduling: Sendable {
    func schedule(
        title: String,
        body: String,
        message: String,
        summary: String?,
        deliverAt: Date?,
        agentID: UUID,
        agentName: String?,
        agentEmoji: String?
    ) async throws -> UUID
}

@MainActor
struct DefaultFollowUpScheduler: FollowUpScheduling {
    var now: @MainActor () -> Date = { Date() }
    let container: ModelContainer
    var contentPreparer: any CommunicationNotificationPreparing =
        SystemCommunicationNotificationPreparer()
    var notificationCenter: any LocalNotificationScheduling = UNUserNotificationCenter.current()

    func schedule(
        title: String,
        body: String,
        message: String,
        summary: String?,
        deliverAt: Date?,
        agentID: UUID,
        agentName: String?,
        agentEmoji: String?
    ) async throws -> UUID {
        let context = ModelContext(container)

        let initiativeRequest = AgentInitiativeRequest(
            agentID: agentID,
            message: message,
            title: title,
            summary: summary
        )
        context.insert(initiativeRequest)
        try context.save()

        let requestID = initiativeRequest.id.uuidString

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = [
            "agentID": agentID.uuidString,
            "notificationTitle": title,
            "message": message,
            "initiativeRequestID": requestID,
        ]

        // A separate thread per request keeps unread notifications from being grouped silently.
        let finalContent: UNNotificationContent = if let name = agentName {
            await contentPreparer.prepare(
                content, agentName: name, agentEmoji: agentEmoji, agentID: agentID,
                conversationID: requestID
            )
        } else {
            content
        }

        do {
            let trigger: UNNotificationTrigger?
            if let deliverAt {
                guard deliverAt > now() else {
                    throw NotificationDeliveryTime
                        .ValidationError(
                            message: "The delivery time elapsed while preparing the notification. Choose a new future time."
                        )
                }
                let components = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute, .second], from: deliverAt
                )
                trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            } else {
                trigger = nil // An omitted time explicitly requests immediate delivery.
            }
            let request = UNNotificationRequest(
                identifier: "backgroundprompt-\(UUID().uuidString)",
                content: finalContent,
                trigger: trigger
            )
            try await notificationCenter.add(request)
        } catch {
            context.delete(initiativeRequest)
            do { try context.save() } catch {
                AppLogger.error(
                    "Failed to clean up notification request: \(private: error.localizedDescription)",
                    category: .backgroundPrompt
                )
            }
            throw error
        }
        return initiativeRequest.id
    }
}
