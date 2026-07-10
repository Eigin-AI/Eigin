import Foundation

/// A single message's metadata, as returned by ``IMAPSession/fetchSummaries(uids:)``.
struct IMAPMessageSummary: Sendable, Equatable {
    let uid: UInt32
    let from: String
    let subject: String
    let date: String
    /// The message's own `Message-ID` header, if present — used to synthesize
    /// a stable thread id and to set `In-Reply-To`/`References` on replies.
    let messageID: String?
}

/// A fully fetched message, as returned by ``IMAPSession/fetchMessage(uid:)``.
struct IMAPFullMessage: Sendable, Equatable {
    let uid: UInt32
    let from: String
    let to: [String]
    let subject: String
    let body: String
    let date: String
    let messageID: String?
}

/// Errors from an ``IMAPSession`` or ``SMTPSession`` operation, kept
/// independent of the underlying client library so callers (and tests) don't
/// need to know about it.
enum MailSessionError: Error, Equatable {
    case authenticationFailed(String)
    case connectionFailed(String)
    case tlsFailed(String)
    case other(String)
}

/// Narrow seam over an IMAP connection, covering only what
/// ``IMAPEmailProvider`` and ``IMAPConnectionVerifier`` need. Exists so the
/// provider's own logic (pagination, query mapping, reply-header
/// construction) can be tested against a fake without a live server or a
/// dependency on the concrete client library.
///
/// A conforming instance is single-use: ``open(settings:)`` connects,
/// authenticates, and selects the inbox; ``close()`` tears the connection
/// down. Callers open a fresh instance per logical operation rather than
/// holding a long-lived connection.
protocol IMAPSession: Sendable {
    func open(settings: IMAPAccountSettings) async throws
    /// UIDs matching `query` (nil matches every message in the inbox), in no
    /// particular order.
    func search(query: String?) async throws -> [UInt32]
    func fetchSummaries(uids: [UInt32]) async throws -> [IMAPMessageSummary]
    /// The full message for `uid`, or `nil` if it no longer exists.
    func fetchMessage(uid: UInt32) async throws -> IMAPFullMessage?
    func close() async
}

/// Narrow seam over an SMTP connection, covering only sending. See
/// ``IMAPSession`` for the rationale.
protocol SMTPSession: Sendable {
    func open(settings: IMAPAccountSettings) async throws
    func send(
        from: String,
        to: [String],
        cc: [String],
        subject: String,
        body: String,
        inReplyTo: String?,
        references: [String]?
    ) async throws
    func close() async
}
