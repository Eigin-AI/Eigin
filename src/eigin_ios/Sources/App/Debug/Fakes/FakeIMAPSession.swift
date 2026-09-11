#if DEBUG || EIGIN_DEV
import Foundation

/// In-memory ``IMAPSession`` for tests — no network access.
final class FakeIMAPSession: IMAPSession, @unchecked Sendable {
    var openError: MailSessionError?
    var searchError: MailSessionError?
    var searchResult: [UInt32] = []
    var summariesByUID: [UInt32: IMAPMessageSummary] = [:]
    var messagesByUID: [UInt32: IMAPFullMessage] = [:]

    private(set) var openedSettings: IMAPAccountSettings?
    private(set) var lastQuery: String??
    private(set) var closeCallCount = 0

    func open(settings: IMAPAccountSettings) async throws {
        if let openError { throw openError }
        openedSettings = settings
    }

    func search(query: String?) async throws -> [UInt32] {
        lastQuery = query
        if let searchError { throw searchError }
        return searchResult
    }

    func fetchSummaries(uids: [UInt32]) async throws -> [IMAPMessageSummary] {
        uids.compactMap { summariesByUID[$0] }
    }

    func fetchMessage(uid: UInt32) async throws -> IMAPFullMessage? {
        messagesByUID[uid]
    }

    func close() async {
        closeCallCount += 1
    }
}
#endif
