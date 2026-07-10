import Foundation
import SwiftMail

/// ``SMTPSession`` backed by SwiftMail's `SMTPServer`.
final class DefaultSMTPSession: SMTPSession, @unchecked Sendable {
    private var server: SMTPServer?

    func open(settings: IMAPAccountSettings) async throws {
        let server = SMTPServer(host: settings.smtpHost, port: settings.smtpPort)
        do {
            try await server.connect()
            try await server.login(username: settings.smtpUsername, password: settings.password)
        } catch {
            throw Self.mapError(error)
        }
        self.server = server
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
        guard let server else { throw MailSessionError.connectionFailed("Session not open") }
        var headers: [String: String] = [:]
        if let inReplyTo {
            headers["In-Reply-To"] = inReplyTo
        }
        if let references, !references.isEmpty {
            headers["References"] = references.joined(separator: " ")
        }
        var email = Email(
            sender: EmailAddress(address: from),
            recipients: to.map { EmailAddress(address: $0) },
            ccRecipients: cc.map { EmailAddress(address: $0) },
            subject: subject,
            textBody: body
        )
        if !headers.isEmpty {
            email.additionalHeaders = headers
        }
        do {
            try await server.sendEmail(email)
        } catch {
            throw Self.mapError(error)
        }
    }

    func close() async {
        try? await server?.disconnect()
        server = nil
    }

    private static func mapError(_ error: Error) -> MailSessionError {
        if let smtpError = error as? SMTPError {
            switch smtpError {
            case .authenticationFailed(let reason):
                return .authenticationFailed(reason)
            case .connectionFailed(let reason):
                return .connectionFailed(reason)
            case .tlsFailed(let reason):
                return .tlsFailed(reason)
            default:
                return .other(String(describing: smtpError))
            }
        }
        return .other(String(describing: error))
    }
}
