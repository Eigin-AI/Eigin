import Foundation
import SwiftData

extension SchemaV14 {
    @Model
    final class AgentInitiativeRequest {
        var id: UUID
        var agentID: UUID
        var message: String
        var title: String?
        var summary: String?
        var createdAt: Date
        var handledAt: Date?
        var dueAt: Date?
        var spaceID: UUID?
        var chatID: UUID?
        var disposition: String?

        init(agentID: UUID, message: String, title: String? = nil, summary: String? = nil) {
            id = UUID()
            self.agentID = agentID
            self.message = message
            self.title = title
            self.summary = summary
            createdAt = .now
            handledAt = nil
        }
    }
}
