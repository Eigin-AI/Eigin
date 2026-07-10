@testable import Eigin
import Foundation
import Testing

/// Verifies ``IMAPEmailProvider``'s own logic — pagination, query forwarding,
/// reply-header construction, and error mapping — against fake sessions.
/// No live IMAP/SMTP server involved.
@Suite("IMAPEmailProvider")
struct IMAPEmailProviderTests {
    private let settings = IMAPAccountSettings(
        emailAddress: "me@example.com",
        imapHost: "imap.example.com",
        smtpHost: "smtp.example.com",
        password: "secret"
    )

    @Test func listEmailsSortsNewestFirstAndPaginates() async throws {
        let integrationID = UUID()
        let credentialStore = FakeIMAPCredentialStore()
        credentialStore.save(settings, for: integrationID)
        let imapSession = FakeIMAPSession()
        imapSession.searchResult = [1, 2, 3, 4, 5]
        for uid in imapSession.searchResult {
            imapSession.summariesByUID[uid] = IMAPMessageSummary(
                uid: uid, from: "a@example.com", subject: "Subject \(uid)", date: "2026-01-01",
                messageID: "<\(uid)@example.com>"
            )
        }
        let provider = IMAPEmailProvider(
            integrationID: integrationID,
            credentialStore: credentialStore,
            makeIMAPSession: { imapSession },
            makeSMTPSession: { FakeSMTPSession() }
        )

        let firstPage = try await provider.listEmails(maxResults: 2, pageToken: nil)
        #expect(firstPage.messages.map(\.id) == ["5", "4"])
        #expect(firstPage.nextPageToken == "2")

        let secondPage = try await provider.listEmails(
            maxResults: 2,
            pageToken: firstPage.nextPageToken
        )
        #expect(secondPage.messages.map(\.id) == ["3", "2"])
        #expect(secondPage.nextPageToken == "4")

        let thirdPage = try await provider.listEmails(
            maxResults: 2,
            pageToken: secondPage.nextPageToken
        )
        #expect(thirdPage.messages.map(\.id) == ["1"])
        #expect(thirdPage.nextPageToken == nil)
    }

    @Test func listEmailsClosesSessionAfterUse() async throws {
        let integrationID = UUID()
        let credentialStore = FakeIMAPCredentialStore()
        credentialStore.save(settings, for: integrationID)
        let imapSession = FakeIMAPSession()
        let provider = IMAPEmailProvider(
            integrationID: integrationID,
            credentialStore: credentialStore,
            makeIMAPSession: { imapSession },
            makeSMTPSession: { FakeSMTPSession() }
        )

        _ = try await provider.listEmails(maxResults: 10, pageToken: nil)
        #expect(imapSession.closeCallCount == 1)
        #expect(imapSession.openedSettings == settings)
    }

    @Test func searchEmailsForwardsQueryToSession() async throws {
        let integrationID = UUID()
        let credentialStore = FakeIMAPCredentialStore()
        credentialStore.save(settings, for: integrationID)
        let imapSession = FakeIMAPSession()
        let provider = IMAPEmailProvider(
            integrationID: integrationID,
            credentialStore: credentialStore,
            makeIMAPSession: { imapSession },
            makeSMTPSession: { FakeSMTPSession() }
        )

        _ = try await provider.searchEmails(query: "invoice", maxResults: 10, pageToken: nil)
        #expect(imapSession.lastQuery == "invoice")
    }

    @Test func readEmailMapsFullMessageAndSynthesizesThreadIDFromMessageID() async throws {
        let integrationID = UUID()
        let credentialStore = FakeIMAPCredentialStore()
        credentialStore.save(settings, for: integrationID)
        let imapSession = FakeIMAPSession()
        imapSession.messagesByUID[42] = IMAPFullMessage(
            uid: 42, from: "alice@example.com", to: ["me@example.com"], subject: "Hi",
            body: "Hello there", date: "2026-01-01", messageID: "<abc@example.com>"
        )
        let provider = IMAPEmailProvider(
            integrationID: integrationID,
            credentialStore: credentialStore,
            makeIMAPSession: { imapSession },
            makeSMTPSession: { FakeSMTPSession() }
        )

        let message = try await provider.readEmail(id: "42")
        #expect(message.id == "42")
        #expect(message.threadID == "<abc@example.com>")
        #expect(message.from == "alice@example.com")
        #expect(message.body == "Hello there")
    }

    @Test func readEmailThrowsNotFoundForNonNumericID() async throws {
        let integrationID = UUID()
        let credentialStore = FakeIMAPCredentialStore()
        credentialStore.save(settings, for: integrationID)
        let provider = IMAPEmailProvider(
            integrationID: integrationID,
            credentialStore: credentialStore,
            makeIMAPSession: { FakeIMAPSession() },
            makeSMTPSession: { FakeSMTPSession() }
        )

        do {
            _ = try await provider.readEmail(id: "not-a-uid")
            Issue.record("Expected an error")
        } catch let error as EmailProviderError {
            guard case .notFound = error else {
                Issue.record("Expected .notFound, got \(error)")
                return
            }
        }
    }

    @Test func readEmailThrowsNotFoundWhenMessageMissing() async throws {
        let integrationID = UUID()
        let credentialStore = FakeIMAPCredentialStore()
        credentialStore.save(settings, for: integrationID)
        let provider = IMAPEmailProvider(
            integrationID: integrationID,
            credentialStore: credentialStore,
            makeIMAPSession: { FakeIMAPSession() },
            makeSMTPSession: { FakeSMTPSession() }
        )

        do {
            _ = try await provider.readEmail(id: "1")
            Issue.record("Expected an error")
        } catch let error as EmailProviderError {
            guard case .notFound = error else {
                Issue.record("Expected .notFound, got \(error)")
                return
            }
        }
    }

    @Test func sendEmailSendsWithNoReplyHeaders() async throws {
        let integrationID = UUID()
        let credentialStore = FakeIMAPCredentialStore()
        credentialStore.save(settings, for: integrationID)
        let smtpSession = FakeSMTPSession()
        let provider = IMAPEmailProvider(
            integrationID: integrationID,
            credentialStore: credentialStore,
            makeIMAPSession: { FakeIMAPSession() },
            makeSMTPSession: { smtpSession }
        )

        let sent = try await provider.sendEmail(
            to: ["bob@example.com"], cc: [], subject: "Hi", body: "Body text"
        )

        #expect(sent.from == settings.emailAddress)
        #expect(smtpSession.sent.count == 1)
        let message = try #require(smtpSession.sent.first)
        #expect(message.to == ["bob@example.com"])
        #expect(message.inReplyTo == nil)
        #expect(message.references == nil)
        #expect(smtpSession.closeCallCount == 1)
    }

    @Test func replyEmailSetsInReplyToAndReferencesFromOriginalMessageID() async throws {
        let integrationID = UUID()
        let credentialStore = FakeIMAPCredentialStore()
        credentialStore.save(settings, for: integrationID)
        let imapSession = FakeIMAPSession()
        imapSession.messagesByUID[7] = IMAPFullMessage(
            uid: 7, from: "alice@example.com", to: ["me@example.com"], subject: "Original",
            body: "hi", date: "2026-01-01", messageID: "<orig@example.com>"
        )
        let smtpSession = FakeSMTPSession()
        let provider = IMAPEmailProvider(
            integrationID: integrationID,
            credentialStore: credentialStore,
            makeIMAPSession: { imapSession },
            makeSMTPSession: { smtpSession }
        )

        let sent = try await provider.replyEmail(messageID: "7", body: "Thanks!")

        #expect(sent.subject == "Re: Original")
        let message = try #require(smtpSession.sent.first)
        #expect(message.to == ["alice@example.com"])
        #expect(message.inReplyTo == "<orig@example.com>")
        #expect(message.references == ["<orig@example.com>"])
    }

    @Test func missingCredentialsThrowsNotAuthenticated() async throws {
        let provider = IMAPEmailProvider(
            integrationID: UUID(),
            credentialStore: FakeIMAPCredentialStore(),
            makeIMAPSession: { FakeIMAPSession() },
            makeSMTPSession: { FakeSMTPSession() }
        )

        do {
            _ = try await provider.listEmails(maxResults: 10, pageToken: nil)
            Issue.record("Expected an error")
        } catch let error as EmailProviderError {
            guard case .notAuthenticated = error else {
                Issue.record("Expected .notAuthenticated, got \(error)")
                return
            }
        }
    }

    @Test func sessionAuthenticationFailureMapsToRequestFailed() async throws {
        let integrationID = UUID()
        let credentialStore = FakeIMAPCredentialStore()
        credentialStore.save(settings, for: integrationID)
        let imapSession = FakeIMAPSession()
        imapSession.openError = .authenticationFailed("bad password")
        let provider = IMAPEmailProvider(
            integrationID: integrationID,
            credentialStore: credentialStore,
            makeIMAPSession: { imapSession },
            makeSMTPSession: { FakeSMTPSession() }
        )

        do {
            _ = try await provider.listEmails(maxResults: 10, pageToken: nil)
            Issue.record("Expected an error")
        } catch let error as EmailProviderError {
            guard case .requestFailed(let reason) = error else {
                Issue.record("Expected .requestFailed, got \(error)")
                return
            }
            #expect(reason.contains("bad password"))
        }
    }
}
