import Foundation

/// An ``EmailProvider`` backend for plain IMAP/SMTP accounts (iCloud,
/// Fastmail, Proton via bridge, and most other providers that aren't reached
/// via OAuth).
///
/// Unlike the OAuth-backed providers, there's no access token to refresh —
/// credentials are the account's own username/password (or app-specific
/// password), read from ``IMAPCredentialStore`` on every call. Each call
/// opens its own session and tears it down afterward (see ``IMAPSession``),
/// mirroring the OAuth providers' stateless-per-call shape.
struct IMAPEmailProvider: EmailProvider {
    let integrationID: UUID
    let credentialStore: any IMAPCredentialStore
    let makeIMAPSession: @Sendable () -> any IMAPSession
    let makeSMTPSession: @Sendable () -> any SMTPSession
    /// Told when authentication is definitively dead (no stored credentials,
    /// or the server rejecting them), so the Connections UI can flag the
    /// reconnect nudge.
    let healthMonitor: (any IntegrationHealthReporter)?

    init(
        integrationID: UUID,
        credentialStore: any IMAPCredentialStore,
        makeIMAPSession: @escaping @Sendable () -> any IMAPSession = { DefaultIMAPSession() },
        makeSMTPSession: @escaping @Sendable () -> any SMTPSession = { DefaultSMTPSession() },
        healthMonitor: (any IntegrationHealthReporter)? = nil
    ) {
        self.integrationID = integrationID
        self.credentialStore = credentialStore
        self.makeIMAPSession = makeIMAPSession
        self.makeSMTPSession = makeSMTPSession
        self.healthMonitor = healthMonitor
    }

    // MARK: - EmailProvider

    func listEmails(maxResults: Int, pageToken: String?) async throws -> EmailPage {
        try await search(query: nil, maxResults: maxResults, pageToken: pageToken)
    }

    func searchEmails(
        query: String,
        maxResults: Int,
        pageToken: String?
    ) async throws -> EmailPage {
        try await search(query: query, maxResults: maxResults, pageToken: pageToken)
    }

    func readEmail(id: String) async throws -> EmailMessage {
        guard let uid = UInt32(id) else { throw EmailProviderError.notFound }
        let settings = try readSettings()
        return try await withIMAPSession(settings) { session in
            guard let message = try await mapErrors({ try await session.fetchMessage(uid: uid) })
            else {
                throw EmailProviderError.notFound
            }
            return Self.emailMessage(from: message)
        }
    }

    func sendEmail(
        to: [String],
        cc: [String],
        subject: String,
        body: String
    ) async throws -> EmailMessage {
        let settings = try readSettings()
        try await withSMTPSession(settings) { session in
            try await mapErrors {
                try await session.send(
                    from: settings.emailAddress,
                    to: to,
                    cc: cc,
                    subject: subject,
                    body: body,
                    inReplyTo: nil,
                    references: nil
                )
            }
        }
        return EmailMessage(
            id: "", threadID: "", from: settings.emailAddress, to: to, subject: subject,
            body: body, date: Self.now()
        )
    }

    func replyEmail(messageID: String, body: String) async throws -> EmailMessage {
        let original = try await readEmail(id: messageID)
        let settings = try readSettings()
        let subject = original.subject.hasPrefix("Re:") ? original.subject : "Re: \(original.subject)"
        // `threadID` is the synthesized Message-ID (see `emailMessage(from:)`) —
        // reuse it as both In-Reply-To and the sole entry of References since
        // IMAP has no server-side thread concept to draw a fuller chain from.
        let inReplyTo = original.threadID.isEmpty ? nil : original.threadID

        try await withSMTPSession(settings) { session in
            try await mapErrors {
                try await session.send(
                    from: settings.emailAddress,
                    to: [original.from],
                    cc: [],
                    subject: subject,
                    body: body,
                    inReplyTo: inReplyTo,
                    references: inReplyTo.map { [$0] }
                )
            }
        }

        return EmailMessage(
            id: "", threadID: original.threadID, from: settings.emailAddress, to: [original.from],
            subject: subject, body: body, date: Self.now()
        )
    }

    // MARK: - Private

    private func readSettings() throws -> IMAPAccountSettings {
        guard let settings = credentialStore.read(for: integrationID) else {
            healthMonitor?.markNeedsReconnect(integrationID)
            throw EmailProviderError.notAuthenticated
        }
        return settings
    }

    private func search(
        query: String?,
        maxResults: Int,
        pageToken: String?
    ) async throws -> EmailPage {
        let settings = try readSettings()
        return try await withIMAPSession(settings) { session in
            let allUIDs = try await mapErrors { try await session.search(query: query) }
            // Newest first: IMAP UIDs are assigned in increasing order over
            // time, so a descending sort approximates newest-first without an
            // extra per-message date fetch just to sort.
            let sorted = allUIDs.sorted(by: >)

            let start = pageToken.flatMap(Int.init) ?? 0
            guard start < sorted.count else {
                return EmailPage(messages: [], nextPageToken: nil)
            }
            let end = min(start + maxResults, sorted.count)
            let pageUIDs = Array(sorted[start ..< end])

            let summaries = try await mapErrors { try await session.fetchSummaries(uids: pageUIDs) }
            // fetchSummaries doesn't promise to preserve request order —
            // reorder to match the page's newest-first order.
            let byUID = Dictionary(uniqueKeysWithValues: summaries.map { ($0.uid, $0) })
            let ordered = pageUIDs.compactMap { byUID[$0] }

            let nextPageToken = end < sorted.count ? String(end) : nil
            return EmailPage(
                messages: ordered.map(Self.emailSummary(from:)),
                nextPageToken: nextPageToken
            )
        }
    }

    /// Opens an ``IMAPSession``, runs `body`, and always closes it afterward
    /// (success or failure) — the per-call connection lifecycle every
    /// operation shares.
    private func withIMAPSession<T: Sendable>(
        _ settings: IMAPAccountSettings,
        _ body: (any IMAPSession) async throws -> T
    ) async throws -> T {
        let session = makeIMAPSession()
        do {
            try await mapErrors { try await session.open(settings: settings) }
            let result = try await body(session)
            await session.close()
            return result
        } catch {
            await session.close()
            throw error
        }
    }

    /// SMTP counterpart to ``withIMAPSession(_:_:)``.
    private func withSMTPSession<T: Sendable>(
        _ settings: IMAPAccountSettings,
        _ body: (any SMTPSession) async throws -> T
    ) async throws -> T {
        let session = makeSMTPSession()
        do {
            try await mapErrors { try await session.open(settings: settings) }
            let result = try await body(session)
            await session.close()
            return result
        } catch {
            await session.close()
            throw error
        }
    }

    /// Runs `body`, mapping any ``MailSessionError`` to the agent-facing
    /// ``EmailProviderError`` the tools layer expects.
    private func mapErrors<T: Sendable>(_ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch let error as MailSessionError {
            switch error {
            case .authenticationFailed(let reason):
                healthMonitor?.markNeedsReconnect(integrationID)
                throw EmailProviderError.requestFailed(
                    "Authentication with the mail server failed — ask the user to reconnect the account in the Eigin app, then try again. \(reason)"
                )
            case .connectionFailed(let reason):
                throw EmailProviderError
                    .requestFailed("Couldn't connect to the mail server: \(reason)")
            case .tlsFailed(let reason):
                throw EmailProviderError.requestFailed("TLS negotiation failed: \(reason)")
            case .other(let reason):
                throw EmailProviderError.requestFailed(reason)
            }
        }
    }

    private static func emailSummary(from summary: IMAPMessageSummary) -> EmailSummary {
        EmailSummary(
            id: String(summary.uid),
            threadID: summary.messageID ?? String(summary.uid),
            from: summary.from,
            subject: summary.subject,
            snippet: "",
            date: summary.date
        )
    }

    private static func emailMessage(from message: IMAPFullMessage) -> EmailMessage {
        EmailMessage(
            id: String(message.uid),
            threadID: message.messageID ?? String(message.uid),
            from: message.from,
            to: message.to,
            subject: message.subject,
            body: message.body,
            date: message.date
        )
    }

    private static func now() -> String {
        ISO8601DateFormatter().string(from: .now)
    }
}
