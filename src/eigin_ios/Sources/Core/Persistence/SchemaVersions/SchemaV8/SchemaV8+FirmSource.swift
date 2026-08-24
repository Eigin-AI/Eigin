import Foundation
import SwiftData

extension SchemaV8 {
    @Model
    final class FirmSource {
        var id: UUID
        var path: String
        var content: String
        var spaceID: UUID?
        var agentID: UUID?
        var chatID: UUID?
        var embedding: [Double]?
        var createdAt: Date
        var updatedAt: Date

        /// How often this entry has been retrieved, weighted by how it was
        /// reached (direct recall counts more than being surfaced indirectly).
        var accessCount: Double = 0

        /// When this entry was last retrieved. Nil until first access.
        var lastAccessedAt: Date?

        /// How critical this entry is, independent of use (0…1). A safety net
        /// for rare-but-important facts.
        var importance: Double = 0.5

        /// Soft-delete flag. Expired entries stay queryable on request but
        /// aren't surfaced by default.
        var expired: Bool = false

        /// Marked when consolidation surfaced a conflict it couldn't resolve and
        /// asked the user. Stops the same question being re-asked every run;
        /// cleared when the conflict resolves.
        var contested: Bool = false

        init(
            path: String,
            content: String,
            spaceID: UUID? = nil,
            agentID: UUID? = nil,
            chatID: UUID? = nil,
            importance: Double = 0.5
        ) {
            id = UUID()
            self.path = path
            self.content = content
            self.spaceID = spaceID
            self.agentID = agentID
            self.chatID = chatID
            self.importance = importance
            embedding = nil
            // Raw init stays neutral (never-accessed); creation-as-access is
            // applied in `addEntity` where an entry is genuinely created, so
            // imports, migrations, and tests don't get phantom usage.
            accessCount = 0
            lastAccessedAt = nil
            expired = false
            contested = false
            createdAt = .now
            updatedAt = .now
        }
    }
}
