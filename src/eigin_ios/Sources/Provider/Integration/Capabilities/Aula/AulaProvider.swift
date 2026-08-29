import Foundation

/// One of the guardian's children as Aula knows them. Captured at connect time
/// and carried in ``AulaSession`` so the agent always has the family context
/// (who the children are, where they go) without an extra round trip.
struct AulaChild: Codable, Equatable, Sendable {
    let id: String
    let name: String
    /// The school or daycare this child attends.
    let institution: String
    /// The child's numeric `institutionProfile.id`, when captured (see
    /// ``DefaultAulaProvider``).
    var institutionProfileID: Int? = nil

    var jsonObject: [String: Any] {
        ["id": id, "name": name, "institution": institution]
    }
}

/// A message thread as it appears in a list — enough for the agent to decide
/// whether to open it in full.
struct AulaMessageSummary: Sendable, Equatable {
    let threadID: String
    let subject: String
    let latestSender: String
    let preview: String
    let unread: Bool
    let date: String

    var jsonObject: [String: Any] {
        [
            "thread_id": threadID,
            "subject": subject,
            "latest_sender": latestSender,
            "preview": preview,
            "unread": unread,
            "date": date,
        ]
    }
}

/// A single message within a thread.
struct AulaMessageEntry: Sendable, Equatable {
    let sender: String
    let text: String
    let date: String

    var jsonObject: [String: Any] {
        ["sender": sender, "text": text, "date": date]
    }
}

/// A fully-read message thread.
struct AulaMessageThread: Sendable, Equatable {
    let threadID: String
    let subject: String
    let messages: [AulaMessageEntry]

    var jsonObject: [String: Any] {
        [
            "thread_id": threadID,
            "subject": subject,
            "messages": messages.map(\.jsonObject),
        ]
    }
}

/// A calendar event (lesson, event, closing day, etc.) for one of the children.
struct AulaCalendarEvent: Sendable, Equatable {
    let id: String
    let title: String
    let start: String
    let end: String
    /// Which child this event belongs to, when Aula attributes it to one.
    let childName: String?
    let location: String?

    var jsonObject: [String: Any] {
        var object: [String: Any] = [
            "id": id,
            "title": title,
            "start": start,
            "end": end,
        ]
        if let childName { object["child"] = childName }
        if let location { object["location"] = location }
        return object
    }
}

/// A notification (Aula's own "you have unread…" style alerts).
struct AulaNotification: Sendable, Equatable {
    let text: String
    let date: String

    var jsonObject: [String: Any] {
        ["text": text, "date": date]
    }
}

/// A post / announcement from a school or group.
struct AulaPost: Sendable, Equatable {
    let id: String
    let title: String
    let content: String
    let author: String
    let date: String

    var jsonObject: [String: Any] {
        ["id": id, "title": title, "content": content, "author": author, "date": date]
    }
}

/// The one-shot digest behind `aula_updates`: what's new and what's coming up,
/// stitched from several endpoints so the agent doesn't have to.
struct AulaUpdatesDigest: Sendable, Equatable {
    let unreadMessageCount: Int
    let recentMessages: [AulaMessageSummary]
    let notifications: [AulaNotification]
    let upcomingEvents: [AulaCalendarEvent]
    let recentPosts: [AulaPost]

    var jsonObject: [String: Any] {
        [
            "unread_message_count": unreadMessageCount,
            "recent_messages": recentMessages.map(\.jsonObject),
            "notifications": notifications.map(\.jsonObject),
            "upcoming_events": upcomingEvents.map(\.jsonObject),
            "recent_posts": recentPosts.map(\.jsonObject),
        ]
    }
}

/// The agent-facing contract for the `aula` capability. Tools depend only on
/// this; ``DefaultAulaProvider`` is the live backend. Expected to evolve as we
/// learn the real API's shape — not a frozen interface.
protocol AulaProvider: Sendable {
    /// The guardian's children and their institutions.
    func children() async throws -> [AulaChild]
    /// A digest of recent and upcoming activity across messages, notifications,
    /// calendar, and posts, over the next/last `days` days.
    func updates(days: Int) async throws -> AulaUpdatesDigest
    /// Message threads, newest first.
    func listMessages(limit: Int) async throws -> [AulaMessageSummary]
    /// The full contents of one thread.
    func readMessage(threadID: String) async throws -> AulaMessageThread
    /// Calendar events between two ISO-8601 dates (inclusive).
    func calendar(from: String, to: String) async throws -> [AulaCalendarEvent]
}

/// Errors surfaced by ``AulaProvider`` implementations to the tools layer.
///
/// Agent/system-facing (they land in tool results and logs), so plain English
/// rather than localized — same convention as ``EmailProviderError``.
enum AulaProviderError: Error, LocalizedError, Equatable {
    case notAuthenticated
    case sessionExpired
    case requestFailed(String)
    case notFound

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            "Not connected to Aula — ask the user to reconnect Aula in the Eigin app, then try again."
        case .sessionExpired:
            "The Aula session has expired — ask the user to reconnect Aula in the Eigin app, then try again."
        case .requestFailed(let reason):
            "Aula request failed: \(reason)"
        case .notFound:
            "Not found in Aula."
        }
    }
}
