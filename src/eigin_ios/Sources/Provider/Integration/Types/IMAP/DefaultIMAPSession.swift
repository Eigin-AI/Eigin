import Foundation
import SwiftMail

/// ``IMAPSession`` backed by SwiftMail's `IMAPServer`.
final class DefaultIMAPSession: IMAPSession, @unchecked Sendable {
    private var server: IMAPServer?
    private var uidValidity: UInt32 = 0
    private let makeServer: @Sendable (IMAPAccountSettings) -> IMAPServer

    init(makeServer: @escaping @Sendable (IMAPAccountSettings) -> IMAPServer = { settings in
        IMAPServer(
            host: settings.imapHost,
            port: settings.imapPort,
            responseBufferLimit: EmailAttachmentLimits.transportBytes
        )
    }) {
        self.makeServer = makeServer
    }

    func open(settings: IMAPAccountSettings) async throws {
        let server = makeServer(settings)
        do {
            try await server.connect()
            try await server.login(username: settings.imapUsername, password: settings.password)
            uidValidity = try await server.selectMailbox("INBOX").uidValidity.value
        } catch {
            throw Self.mapError(error)
        }
        self.server = server
    }

    func search(query: String?) async throws -> [UInt32] {
        guard let server else { throw MailSessionError.connectionFailed("Session not open") }
        do {
            let criteria: SearchCriteria = query.map { .text($0) } ?? .all
            let result: ExtendedSearchResult<UID> = try await server
                .extendedSearch(criteria: [criteria])
            return result.all?.toArray().map(\.value) ?? []
        } catch {
            throw Self.mapError(error)
        }
    }

    func fetchSummaries(uids: [UInt32]) async throws -> [IMAPMessageSummary] {
        guard let server else { throw MailSessionError.connectionFailed("Session not open") }
        guard !uids.isEmpty else { return [] }
        do {
            let set = UIDSet(uids.map { UID($0) })
            let infos = try await server.fetchMessageInfosBulk(
                using: set,
                options: SwiftMail.FetchMessageInfoOptions.slim
            )
            return infos.map(Self.summary(from:))
        } catch {
            throw Self.mapError(error)
        }
    }

    func fetchMessage(uid: UInt32) async throws -> IMAPFullMessage? {
        guard let server else { throw MailSessionError.connectionFailed("Session not open") }
        do {
            guard let header = try await server.fetchMessageInfo(for: UID(uid)) else {
                return nil
            }
            let parts = try await server.fetchStructure(UID(uid))
            let attachmentSections = parts.filter(Self.isAttachment).map { $0.section.components }
            let visibleParts = parts.filter { part in
                !attachmentSections.contains { parent in
                    part.section.components.count > parent.count && part.section.components
                        .starts(with: parent)
                }
            }
            var bodyParts: [MessagePart] = []
            for var part in visibleParts
                where !Self.isAttachment(part) && ["text/plain", "text/html"]
                .contains(Self.mediaType(part))
            {
                try Task.checkCancellation()
                part.data = try await server.fetchPart(section: part.section, of: UID(uid))
                bodyParts.append(part)
            }
            let message = SwiftMail.Message(header: header, parts: bodyParts)
            var result = Self.fullMessage(uid: uid, header: header, message: message)
            result.attachments = visibleParts.filter(Self.isAttachment)
                .map { metadata($0, uid: uid) }
            return result
        } catch {
            throw Self.mapError(error)
        }
    }

    private static func mediaType(_ part: MessagePart) -> String {
        part.contentType.components(separatedBy: ";")[0].trimmingCharacters(in: .whitespaces)
            .lowercased()
    }

    private static func isAttachment(_ part: MessagePart) -> Bool {
        if part.disposition?.lowercased() == "attachment" { return true }
        guard ["text/plain", "text/html"].contains(mediaType(part)) else { return true }
        guard let filename = part.filename, !filename.isEmpty else { return false }
        // SwiftMail uses a decoded Content-ID as the filename when MIME filename parameters are
        // absent.
        let contentIDName = part.contentId?.trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
            .decodeMIMEHeader()
        return filename != contentIDName
    }

    private func metadata(_ part: MessagePart, uid: UInt32) -> EmailAttachment {
        EmailAttachment(
            id: "\(uidValidity):\(uid):\(part.section)",
            filename: part.filename ?? "attachment",
            mimeType: part.contentType,
            unsupportedReason: "IMAP attachment downloads are not supported yet."
        )
    }

    func close() async {
        try? await server?.disconnect()
        server = nil
    }

    // MARK: - Mapping

    private static func summary(from info: MessageInfo) -> IMAPMessageSummary {
        IMAPMessageSummary(
            uid: info.uid?.value ?? 0,
            from: info.from ?? "",
            subject: info.subject ?? "",
            date: (info.date ?? info.internalDate).map(formatted(_:)) ?? "",
            messageID: info.messageId?.description
        )
    }

    private static func fullMessage(
        uid: UInt32,
        header: MessageInfo,
        message: SwiftMail.Message
    ) -> IMAPFullMessage {
        IMAPFullMessage(
            uid: uid,
            from: header.from ?? "",
            to: header.to,
            subject: header.subject ?? "",
            body: message.textBody ?? stripHTML(message.htmlBody) ?? "",
            date: (header.date ?? header.internalDate).map(formatted(_:)) ?? "",
            messageID: header.messageId?.description
        )
    }

    private static func formatted(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    /// A minimal fallback for HTML-only messages: strips tags so the agent
    /// gets readable text rather than markup. Not a full HTML renderer.
    private static func stripHTML(_ html: String?) -> String? {
        guard let html else { return nil }
        let stripped = html.replacingOccurrences(
            of: "<[^>]+>", with: "", options: .regularExpression
        )
        return stripped.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func mapError(_ error: Error) -> MailSessionError {
        if let imapError = error as? IMAPError {
            switch imapError {
            case .loginFailed(let reason), .authFailed(let reason):
                return .authenticationFailed(reason)
            case .connectionFailed(let reason), .greetingFailed(let reason):
                return .connectionFailed(reason)
            default:
                return .other(String(describing: imapError))
            }
        }
        return .other(String(describing: error))
    }
}
