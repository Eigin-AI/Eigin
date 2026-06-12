import Foundation

/// A discrete unit of work tracked under an ``Intent``.
///
/// Tasks let the agent break a goal into a checklist it can complete over time.
/// They have no independent lifecycle — they live and die with their intent and
/// are persisted as part of it.
struct IntentTask: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var content: String
    var due: Date?
    var priority: TaskPriority?
    var completed: Bool
    /// Free-text note on what's holding the task up (e.g. a person or dependency).
    var blockedBy: String?

    init(
        id: UUID = UUID(),
        content: String,
        due: Date? = nil,
        priority: TaskPriority? = nil,
        completed: Bool = false,
        blockedBy: String? = nil
    ) {
        self.id = id
        self.content = content
        self.due = due
        self.priority = priority
        self.completed = completed
        self.blockedBy = blockedBy
    }
}

/// Relative importance of a task, used as a tie-breaker when surfacing work.
enum TaskPriority: String, Codable, CaseIterable, Sendable {
    case high
    case medium
    case low
}
