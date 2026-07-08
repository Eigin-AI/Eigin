import Foundation

/// A single message in a list/search result — enough to let the agent decide
/// whether to read it in full.
struct EmailSummary: Sendable, Equatable {
    let id: String
    /// Groups messages into a conversation. A Gmail concept (`threadId`) —
    /// not part of any email standard, so a future non-Gmail backend (e.g.
    /// IMAP, which has no native thread id) may need to make this optional
    /// or synthesize one from References/In-Reply-To headers.
    let threadID: String
    let from: String
    let subject: String
    let snippet: String
    let date: String
}

/// One page of list/search results, with a token to fetch the next page.
struct EmailPage: Sendable, Equatable {
    let messages: [EmailSummary]
    /// Pass back as `pageToken` to fetch the next page. `nil` means this was
    /// the last page.
    let nextPageToken: String?
}

/// A fully-read message.
struct EmailMessage: Sendable, Equatable {
    let id: String
    /// See ``EmailSummary/threadID``.
    let threadID: String
    let from: String
    let to: [String]
    let subject: String
    let body: String
    let date: String
}

/// The agent-facing contract for the `email` capability. Backends (Gmail
/// today; IMAP or another provider could implement this later) conform to
/// this protocol — the five email tools, the email skill, and the resolution
/// rule never see the backend, only this contract. Expected to evolve as
/// more backends land, not a frozen interface.
protocol EmailProvider: Sendable {
    func listEmails(maxResults: Int, pageToken: String?) async throws -> EmailPage
    func searchEmails(
        query: String,
        maxResults: Int,
        pageToken: String?
    ) async throws -> EmailPage
    func readEmail(id: String) async throws -> EmailMessage
    /// Sends the message and returns it as sent, so the agent keeps the
    /// subject/body it just committed to even if the tool call's own
    /// arguments later drop out of context.
    func sendEmail(to: [String], cc: [String], subject: String, body: String) async throws
        -> EmailMessage
    /// Replies within the thread of `messageID`. Returns the sent message.
    func replyEmail(messageID: String, body: String) async throws -> EmailMessage
}

extension EmailMessage {
    var jsonObject: [String: Any] {
        [
            "id": id,
            "thread_id": threadID,
            "from": from,
            "to": to,
            "subject": subject,
            "body": body,
            "date": date,
        ]
    }
}

/// Errors surfaced by ``EmailProvider`` implementations to the tools layer.
///
/// Agent/system-facing, not user-facing: these strings land in tool results
/// (and from there, logs), not directly in a user-visible alert, so they're
/// deliberately plain English rather than localized. A view that wants to
/// show something to the user should present its own copy, not this text.
enum EmailProviderError: Error, LocalizedError {
    case notAuthenticated
    case requestFailed(String)
    case notFound

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            "Not authenticated with the email provider."
        case .requestFailed(let reason):
            "Email request failed: \(reason)"
        case .notFound:
            "Message not found."
        }
    }
}
