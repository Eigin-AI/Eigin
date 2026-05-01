import Foundation
import SwiftData

extension SchemaV1 {
    @Model
    final class Space {
        var id: UUID
        var agentID: UUID
        var name: String = ""
        var emoji: String = "📁"
        var instructions: String = ""
        var bootstrapComplete: Bool = false
        var isPrivate: Bool = false
        var createdAt: Date
        var updatedAt: Date

        init(agentID: UUID) {
            id = UUID()
            self.agentID = agentID
            createdAt = .now
            updatedAt = .now
        }
    }
}
