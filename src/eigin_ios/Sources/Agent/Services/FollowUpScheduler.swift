import Foundation
import SwiftData
import UserNotifications

/// Adds local notification requests to the system notification center.
@MainActor
protocol LocalNotificationScheduling: Sendable {
    func add(_ request: UNNotificationRequest) async throws
    func pendingNotificationRequests() async -> [UNNotificationRequest]
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

/// System delivery outcome after the follow-up has been durably saved.
enum FollowUpDeliveryStatus: String {
    case scheduled = "notification_scheduled"
    case permissionDenied = "permission_denied"
    case capacityExceeded = "capacity_exceeded"
    case failed = "notification_failed"
}

/// A saved follow-up survives every optional system-delivery failure.
struct FollowUpScheduleResult {
    let requestID: UUID
    let dueAt: Date
    let deliveryStatus: FollowUpDeliveryStatus
}

/// Persists prepared follow-ups before attempting optional notification delivery.
@MainActor protocol FollowUpScheduling: Sendable {
    func schedule(
        title: String, body: String, message: String, summary: String?, deliverAt: Date?,
        agentID: UUID, agentName: String?, agentEmoji: String?, spaceID: UUID?, canPromptUser: Bool
    ) async throws -> FollowUpScheduleResult
}

@MainActor struct DefaultFollowUpScheduler: FollowUpScheduling {
    var now: @MainActor () -> Date = { Date() }
    let container: ModelContainer
    var contentPreparer: any CommunicationNotificationPreparing =
        SystemCommunicationNotificationPreparer()
    var notificationCenter: any LocalNotificationScheduling = UNUserNotificationCenter.current()
    var authorize: @MainActor (Bool) async
        -> Bool = { await NotificationPermission.requestIfNeeded(canPromptUser: $0) }
    var onChange: @MainActor () -> Void = {}

    func schedule(
        title: String, body: String, message: String, summary: String?, deliverAt: Date?,
        agentID: UUID, agentName: String?, agentEmoji: String?, spaceID: UUID? = nil,
        canPromptUser: Bool = true
    ) async throws -> FollowUpScheduleResult {
        let instant = now()
        let context = ModelContext(container)
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              deliverAt == nil || deliverAt! > instant,
              try WaitingMessageStore.validScope(
                  agentID: agentID,
                  spaceID: spaceID,
                  context: context
              )
        else { throw InitiativeError.invalidContent }
        let saved = AgentInitiativeRequest(
            agentID: agentID,
            message: message,
            title: title,
            summary: summary
        )
        saved.dueAt = deliverAt ?? instant
        saved.spaceID = spaceID
        context.insert(saved)
        do { try context.save() } catch { context.rollback(); throw error }
        onChange()

        func result(_ status: FollowUpDeliveryStatus) -> FollowUpScheduleResult {
            FollowUpScheduleResult(
                requestID: saved.id,
                dueAt: deliverAt ?? instant,
                deliveryStatus: status
            )
        }
        guard await authorize(canPromptUser) else { return result(.permissionDenied) }
        if deliverAt != nil, await notificationCenter.pendingNotificationRequests().count >= 64 {
            return result(.capacityExceeded)
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = [
            "agentID": agentID.uuidString, "notificationTitle": title,
            "message": message, "initiativeRequestID": saved.id.uuidString,
        ]
        let finalContent: UNNotificationContent = if let name = agentName {
            await contentPreparer.prepare(
                content,
                agentName: name,
                agentEmoji: agentEmoji,
                agentID: agentID,
                conversationID: saved.id.uuidString
            )
        } else { content }
        // A message may have been opened or discarded while permission/presentation was awaited.
        let fresh = ModelContext(container)
        guard let current = try? fresh.fetch(FetchDescriptor<AgentInitiativeRequest>())
            .first(where: { $0.id == saved.id }),
            current.handledAt == nil, current.disposition == nil else { return result(.failed) }
        let trigger: UNNotificationTrigger?
        if let deliverAt {
            guard deliverAt > now() else { onChange(); return result(.failed) }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            // Calendar triggers have second precision; never deliver before the saved due time.
            let notificationDate =
                Date(timeIntervalSince1970: ceil(deliverAt.timeIntervalSince1970))
            var components = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: notificationDate
            )
            components.timeZone = calendar.timeZone
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        } else { trigger = nil }
        do {
            try await notificationCenter.add(UNNotificationRequest(
                identifier: "follow-up-\(saved.id.uuidString)", content: finalContent,
                trigger: trigger
            ))
            onChange()
            return result(.scheduled)
        } catch {
            return result(.failed)
        }
    }
}
