@testable import Eigin
import Foundation
import UserNotifications

@MainActor
final class RecordingCommunicationNotificationPreparer: CommunicationNotificationPreparing {
    struct Call {
        let agentName: String
        let agentEmoji: String?
        let agentID: UUID
        let conversationID: String
    }

    private(set) var calls: [Call] = []

    func prepare(
        _ content: UNMutableNotificationContent,
        agentName: String,
        agentEmoji: String?,
        agentID: UUID,
        conversationID: String
    ) async -> UNNotificationContent {
        calls.append(Call(
            agentName: agentName,
            agentEmoji: agentEmoji,
            agentID: agentID,
            conversationID: conversationID
        ))
        let prepared = content.mutableCopy() as! UNMutableNotificationContent
        prepared.subtitle = "Prepared communication"
        return prepared
    }
}
