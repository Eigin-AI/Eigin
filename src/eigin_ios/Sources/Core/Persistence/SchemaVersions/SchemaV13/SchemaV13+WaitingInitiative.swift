import Foundation
import SwiftData

extension SchemaV13 {
    /// Durable high-water mark; removed invitations cannot be rediscovered.
    @Model final class InitiativeCursor {
        var initiativeID: UUID
        var revision: String
        var evaluatedThrough: Date
        var timeZoneIdentifier: String

        init(
            initiativeID: UUID,
            revision: String,
            evaluatedThrough: Date,
            timeZoneIdentifier: String
        ) {
            self.initiativeID = initiativeID
            self.revision = revision
            self.evaluatedThrough = evaluatedThrough
            self.timeZoneIdentifier = timeZoneIdentifier
        }
    }

    /// A due invitation with an immutable execution snapshot, before a chat exists.
    @Model final class WaitingInitiative {
        var id: String
        var initiativeID: UUID
        var revision: String
        var agentID: UUID
        var spaceID: UUID?
        var dueAt: Date
        var registrationID: String
        var body: String

        init(
            id: String,
            initiativeID: UUID,
            revision: String,
            agentID: UUID,
            spaceID: UUID?,
            dueAt: Date,
            registrationID: String,
            body: String
        ) {
            self.id = id
            self.initiativeID = initiativeID
            self.revision = revision
            self.agentID = agentID
            self.spaceID = spaceID
            self.dueAt = dueAt
            self.registrationID = registrationID
            self.body = body
        }
    }
}
