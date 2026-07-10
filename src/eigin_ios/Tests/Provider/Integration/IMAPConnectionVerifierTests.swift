@testable import Eigin
import Foundation
import Testing

/// Verifies ``IMAPConnectionVerifier``'s error mapping and IMAP-then-SMTP
/// ordering against fake sessions — no live server involved.
@Suite("IMAPConnectionVerifier")
struct IMAPConnectionVerifierTests {
    private let settings = IMAPAccountSettings(
        emailAddress: "me@example.com",
        imapHost: "imap.example.com",
        smtpHost: "smtp.example.com",
        password: "secret"
    )

    @Test func succeedsWhenBothSessionsOpen() async throws {
        let imapSession = FakeIMAPSession()
        let smtpSession = FakeSMTPSession()

        try await IMAPConnectionVerifier.verify(
            settings,
            makeIMAPSession: { imapSession },
            makeSMTPSession: { smtpSession }
        )

        #expect(imapSession.openedSettings == settings)
        #expect(smtpSession.openedSettings == settings)
        #expect(imapSession.closeCallCount == 1)
        #expect(smtpSession.closeCallCount == 1)
    }

    @Test func imapFailureStopsBeforeTryingSMTP() async throws {
        let imapSession = FakeIMAPSession()
        imapSession.openError = .authenticationFailed("bad password")
        let smtpSession = FakeSMTPSession()

        do {
            try await IMAPConnectionVerifier.verify(
                settings,
                makeIMAPSession: { imapSession },
                makeSMTPSession: { smtpSession }
            )
            Issue.record("Expected an error")
        } catch let error as IMAPConnectionError {
            guard case .imapAuthFailed(let reason) = error else {
                Issue.record("Expected .imapAuthFailed, got \(error)")
                return
            }
            #expect(reason == "bad password")
        }

        #expect(smtpSession.openedSettings == nil)
    }

    @Test func smtpFailureAfterSuccessfulIMAPSurfacesSMTPError() async throws {
        let imapSession = FakeIMAPSession()
        let smtpSession = FakeSMTPSession()
        smtpSession.openError = .connectionFailed("timed out")

        do {
            try await IMAPConnectionVerifier.verify(
                settings,
                makeIMAPSession: { imapSession },
                makeSMTPSession: { smtpSession }
            )
            Issue.record("Expected an error")
        } catch let error as IMAPConnectionError {
            guard case .smtpConnectionFailed(let reason) = error else {
                Issue.record("Expected .smtpConnectionFailed, got \(error)")
                return
            }
            #expect(reason == "timed out")
        }

        #expect(imapSession.openedSettings == settings)
    }

    @Test func errorDescriptionsAreLocalizedAndIncludeReason() {
        let error = IMAPConnectionError.imapAuthFailed("invalid credentials")
        #expect(error.errorDescription?.contains("invalid credentials") == true)
    }
}
