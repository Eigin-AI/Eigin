@testable import Eigin
import Foundation

/// In-memory ``SMTPSession`` for tests — no network access.
final class FakeSMTPSession: SMTPSession, @unchecked Sendable {
    var openError: MailSessionError?
    var sendError: MailSessionError?

    private(set) var openedSettings: IMAPAccountSettings?
    private(set) var closeCallCount = 0

    struct SentMessage: Equatable {
        let from: String
        let to: [String]
        let cc: [String]
        let subject: String
        let body: String
        let inReplyTo: String?
        let references: [String]?
    }

    private(set) var sent: [SentMessage] = []

    func open(settings: IMAPAccountSettings) async throws {
        if let openError { throw openError }
        openedSettings = settings
    }

    func send(
        from: String,
        to: [String],
        cc: [String],
        subject: String,
        body: String,
        inReplyTo: String?,
        references: [String]?
    ) async throws {
        if let sendError { throw sendError }
        sent.append(SentMessage(
            from: from, to: to, cc: cc, subject: subject, body: body,
            inReplyTo: inReplyTo, references: references
        ))
    }

    func close() async {
        closeCallCount += 1
    }
}
