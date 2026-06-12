import Foundation

/// A one-off temporal trigger attached to an ``Intent``.
///
/// Events tie a goal to a fixed moment — a birthday, a deadline, an appointment.
/// As the event's date approaches, the intent's relevance rises (see
/// ``IntentRelevance``) so the agent surfaces it at the right time.
struct IntentEvent: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var content: String
    /// When the event occurs.
    var at: Date

    init(id: UUID = UUID(), content: String, at: Date) {
        self.id = id
        self.content = content
        self.at = at
    }
}
