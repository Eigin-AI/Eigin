import Foundation
import SwiftData

extension SchemaV2 {
    /// An agent goal that persists until explicitly resolved.
    ///
    /// V2 drops the V1 decay model (`reinforcedCount`, `effectiveStrength`):
    /// intents no longer fade on their own. Instead they carry optional
    /// ``IntentTask``s, ``IntentEvent``s, and ``IntentSchedule``s, and their
    /// ordering is derived from temporal relevance (see ``IntentRelevance``).
    @Model
    final class Intent {
        var id: UUID
        var agentID: UUID
        var spaceID: UUID?
        var chatID: UUID?
        var content: String
        var status: String
        var tasks: [IntentTask] = []
        var events: [IntentEvent] = []
        var schedules: [IntentSchedule] = []
        var createdAt: Date
        var updatedAt: Date

        init(
            agentID: UUID,
            content: String,
            spaceID: UUID? = nil,
            chatID: UUID? = nil,
            tasks: [IntentTask] = [],
            events: [IntentEvent] = [],
            schedules: [IntentSchedule] = []
        ) {
            id = UUID()
            self.agentID = agentID
            self.spaceID = spaceID
            self.chatID = chatID
            self.content = content
            status = IntentStatus.active.rawValue
            self.tasks = tasks
            self.events = events
            self.schedules = schedules
            createdAt = .now
            updatedAt = .now
        }

        var intentStatus: IntentStatus {
            get { IntentStatus(rawValue: status) ?? .active }
            set { status = newValue.rawValue }
        }

        var isActive: Bool {
            intentStatus == .active
        }
    }
}
