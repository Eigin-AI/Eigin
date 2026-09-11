#if DEBUG || EIGIN_DEV
import Foundation

/// Configurable fake ``EmailProvider`` for exercising the email tools in
/// isolation from any real backend.
final class FakeEmailProvider: EmailProvider, @unchecked Sendable {
    var summaries: [EmailSummary] = []
    var nextPageToken: String?
    var message: EmailMessage = .init(
        id: "msg-1", threadID: "thread-1", from: "alice@example.com",
        to: ["me@example.com"], subject: "Hello", body: "Hi there", date: "2026-01-01"
    )
    var sendResult: EmailMessage = .init(
        id: "sent-1", threadID: "thread-1", from: "me@example.com",
        to: ["bob@example.com"], subject: "Subject", body: "Body", date: "2026-01-02"
    )
    var replyResult: EmailMessage = .init(
        id: "reply-1", threadID: "thread-1", from: "me@example.com",
        to: ["alice@example.com"], subject: "Re: Hello", body: "Reply body", date: "2026-01-03"
    )
    var errorToThrow: Error?

    private(set) var lastSearchQuery: String?
    private(set) var lastPageToken: String?
    private(set) var lastReadID: String?
    private(set) var lastSendTo: [String]?
    private(set) var lastSendBody: String?
    private(set) var lastReplyMessageID: String?
    private(set) var lastReplyBody: String?

    func listEmails(maxResults: Int, pageToken: String?) async throws -> EmailPage {
        if let errorToThrow { throw errorToThrow }
        lastPageToken = pageToken
        return EmailPage(messages: summaries, nextPageToken: nextPageToken)
    }

    func searchEmails(
        query: String,
        maxResults: Int,
        pageToken: String?
    ) async throws -> EmailPage {
        if let errorToThrow { throw errorToThrow }
        lastSearchQuery = query
        lastPageToken = pageToken
        return EmailPage(messages: summaries, nextPageToken: nextPageToken)
    }

    func readEmail(id: String) async throws -> EmailMessage {
        if let errorToThrow { throw errorToThrow }
        lastReadID = id
        return message
    }

    func sendEmail(
        to: [String],
        cc: [String],
        subject: String,
        body: String
    ) async throws -> EmailMessage {
        if let errorToThrow { throw errorToThrow }
        lastSendTo = to
        lastSendBody = body
        return sendResult
    }

    func replyEmail(messageID: String, body: String) async throws -> EmailMessage {
        if let errorToThrow { throw errorToThrow }
        lastReplyMessageID = messageID
        lastReplyBody = body
        return replyResult
    }
}
#endif
