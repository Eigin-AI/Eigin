import Foundation
import SwiftData

extension SchemaV1 {
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

        init(
            path: String,
            content: String,
            spaceID: UUID? = nil,
            agentID: UUID? = nil,
            chatID: UUID? = nil
        ) {
            id = UUID()
            self.path = path
            self.content = content
            self.spaceID = spaceID
            self.agentID = agentID
            self.chatID = chatID
            createdAt = .now
            updatedAt = .now
        }
    }
}
