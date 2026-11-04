import Foundation
import SwiftData

extension SchemaV11 {
    /// An explicit notification agreement attached to an intent schedule.
    @Model final class IntentInitiative {
        var id: UUID
        var intentID: UUID
        var scheduleID: UUID
        var instructions: String
        var notificationBody: String
        var enabled: Bool
        var updatedAt: Date
        var schedulingError: String?
        var registrationStatus: String = "pending"

        init(
            id: UUID = UUID(),
            intentID: UUID,
            scheduleID: UUID,
            instructions: String,
            notificationBody: String
        ) {
            self.id = id
            self.intentID = intentID
            self.scheduleID = scheduleID
            self.instructions = instructions
            self.notificationBody = notificationBody
            enabled = true
            updatedAt = .now
        }
    }

    /// Immutable delivery payload retained so old delivered notifications can be validated.
    @Model final class InitiativeRegistration {
        var id: String
        var payload: Data
        var createdAt: Date
        var retiredAt: Date?

        init(id: String, payload: Data) {
            self.id = id
            self.payload = payload
            createdAt = .now
        }
    }

    /// Durable occurrence-to-chat claim; a repeated tap never creates another turn.
    @Model final class InitiativeOccurrence {
        var id: String
        var registrationID: String
        var deliveredAt: Date
        var chatID: UUID
        var intentIDs: [UUID]
        var startedAt: Date?
        var completedAt: Date?
        var outputMessageIDs: [UUID] = []

        init(
            id: String,
            registrationID: String,
            deliveredAt: Date,
            chatID: UUID,
            intentIDs: [UUID]
        ) {
            self.id = id
            self.registrationID = registrationID
            self.deliveredAt = deliveredAt
            self.chatID = chatID
            self.intentIDs = intentIDs
        }
    }
}
