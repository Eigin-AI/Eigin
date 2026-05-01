import Foundation
import SwiftData

extension SchemaV1 {
    @Model
    final class Intent {
        var id: UUID
        var agentID: UUID
        var spaceID: UUID?
        var chatID: UUID?
        var content: String
        var status: String
        var reinforcedCount: Int = 0
        var createdAt: Date
        var updatedAt: Date

        init(agentID: UUID, content: String, spaceID: UUID? = nil, chatID: UUID? = nil) {
            id = UUID()
            self.agentID = agentID
            self.spaceID = spaceID
            self.chatID = chatID
            self.content = content
            status = IntentStatus.active.rawValue
            createdAt = .now
            updatedAt = .now
        }

        var intentStatus: IntentStatus {
            get { IntentStatus(rawValue: status) ?? .active }
            set { status = newValue.rawValue }
        }

        /// Effective strength decays over time. Half-life grows with reinforcement.
        var effectiveStrength: Double {
            let days = max(0, Date.now.timeIntervalSince(updatedAt) / 86400)
            let halfLife = Double(min(
                IntentDecay.baseHalfLifeDays + IntentDecay.reinforcementBonusDays * reinforcedCount,
                IntentDecay.maxHalfLifeDays
            ))
            return exp(-days / halfLife)
        }

        var isActive: Bool {
            intentStatus == .active && effectiveStrength > IntentDecay.activeThreshold
        }
    }
}
