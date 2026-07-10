import Foundation

/// Verifies a manually entered ``IMAPAccountSettings`` by actually connecting
/// — the IMAP counterpart to the OAuth flows' redirect-and-token-exchange
/// round trip, which itself proves the credentials work. Connects to *both*
/// IMAP and SMTP so a broken send path (a common misconfiguration — wrong
/// SMTP username/port) is caught before the integration is saved, not on the
/// agent's first send attempt.
enum IMAPConnectionVerifier {
    static func verify(
        _ settings: IMAPAccountSettings,
        makeIMAPSession: @Sendable () -> any IMAPSession = { DefaultIMAPSession() },
        makeSMTPSession: @Sendable () -> any SMTPSession = { DefaultSMTPSession() }
    ) async throws {
        let imapSession = makeIMAPSession()
        do {
            try await imapSession.open(settings: settings)
        } catch let error as MailSessionError {
            await imapSession.close()
            throw IMAPConnectionError.imap(error)
        }
        await imapSession.close()

        let smtpSession = makeSMTPSession()
        do {
            try await smtpSession.open(settings: settings)
        } catch let error as MailSessionError {
            await smtpSession.close()
            throw IMAPConnectionError.smtp(error)
        }
        await smtpSession.close()
    }
}

/// User-facing: surfaced directly in ``AddIMAPAccount``'s error UI, so unlike
/// ``EmailProviderError`` these are localized.
enum IMAPConnectionError: Error, LocalizedError, Equatable {
    case imapAuthFailed(String)
    case imapConnectionFailed(String)
    case smtpAuthFailed(String)
    case smtpConnectionFailed(String)
    case tlsFailed(String)
    case unknown(String)

    static func imap(_ error: MailSessionError) -> IMAPConnectionError {
        switch error {
        case .authenticationFailed(let reason): .imapAuthFailed(reason)
        case .connectionFailed(let reason): .imapConnectionFailed(reason)
        case .tlsFailed(let reason): .tlsFailed(reason)
        case .other(let reason): .unknown(reason)
        }
    }

    static func smtp(_ error: MailSessionError) -> IMAPConnectionError {
        switch error {
        case .authenticationFailed(let reason): .smtpAuthFailed(reason)
        case .connectionFailed(let reason): .smtpConnectionFailed(reason)
        case .tlsFailed(let reason): .tlsFailed(reason)
        case .other(let reason): .unknown(reason)
        }
    }

    var errorDescription: String? {
        switch self {
        case .imapAuthFailed(let reason):
            Localized.Errors.Imap.authFailed(reason)
        case .imapConnectionFailed(let reason):
            Localized.Errors.Imap.connectionFailed(reason)
        case .smtpAuthFailed(let reason):
            Localized.Errors.Imap.smtpAuthFailed(reason)
        case .smtpConnectionFailed(let reason):
            Localized.Errors.Imap.smtpConnectionFailed(reason)
        case .tlsFailed(let reason):
            Localized.Errors.Imap.tlsFailed(reason)
        case .unknown(let reason):
            Localized.Errors.Imap.unknown(reason)
        }
    }
}
