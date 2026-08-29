import Foundation

/// An ``EmailProvider`` backend for Gmail, using its REST API.
///
/// Handles plain-text bodies only; HTML-only messages fall back to the snippet.
struct GmailEmailProvider: EmailProvider {
    let integrationID: UUID
    let oauthService: any IntegrationOAuthService
    let oauthConfig: PKCEOAuthConfig
    let urlSession: URLSession
    /// Told when authentication is definitively dead (no stored token), so the
    /// Connections UI can flag the reconnect nudge.
    let healthMonitor: (any IntegrationHealthReporter)?

    private static let baseURL = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me")!

    init(
        integrationID: UUID,
        oauthService: any IntegrationOAuthService,
        oauthConfig: PKCEOAuthConfig,
        urlSession: URLSession = .shared,
        healthMonitor: (any IntegrationHealthReporter)? = nil
    ) {
        self.integrationID = integrationID
        self.oauthService = oauthService
        self.oauthConfig = oauthConfig
        self.urlSession = urlSession
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
        let token = try await accessToken()
        var components = URLComponents(
            url: Self.baseURL.appendingPathComponent("messages/\(id)"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "format", value: "full")]
        let data = try await get(components.url!, token: token)
        let raw = try JSONDecoder().decode(GmailMessage.self, from: data)
        return raw.toEmailMessage()
    }

    func sendEmail(
        to: [String],
        cc: [String],
        subject: String,
        body: String
    ) async throws -> EmailMessage {
        let token = try await accessToken()
        let rfc822 = Self.buildRFC822(to: to, cc: cc, subject: subject, body: body)
        let sentID = try await send(raw: rfc822, token: token)
        return try await readEmail(id: sentID)
    }

    func replyEmail(messageID: String, body: String) async throws -> EmailMessage {
        let original = try await readEmail(id: messageID)
        let token = try await accessToken()
        let subject = original.subject.hasPrefix("Re:") ? original.subject : "Re: \(original.subject)"
        let rfc822 = Self.buildRFC822(
            to: [original.from],
            cc: [],
            subject: subject,
            body: body,
            inReplyTo: messageID,
            threadID: original.threadID
        )
        let sentID = try await send(raw: rfc822, token: token, threadID: original.threadID)
        return try await readEmail(id: sentID)
    }

    // MARK: - Private

    private func accessToken() async throws -> String {
        guard let token = try await oauthService.validToken(
            config: oauthConfig,
            integrationID: integrationID
        ) else {
            healthMonitor?.markNeedsReconnect(integrationID)
            throw EmailProviderError.notAuthenticated
        }
        return token
    }

    private func search(
        query: String?,
        maxResults: Int,
        pageToken: String?
    ) async throws -> EmailPage {
        let token = try await accessToken()
        var components = URLComponents(
            url: Self.baseURL.appendingPathComponent("messages"),
            resolvingAgainstBaseURL: false
        )!
        var items = [URLQueryItem(name: "maxResults", value: "\(maxResults)")]
        if let query {
            items.append(URLQueryItem(name: "q", value: query))
        }
        if let pageToken {
            items.append(URLQueryItem(name: "pageToken", value: pageToken))
        }
        components.queryItems = items

        let data = try await get(components.url!, token: token)
        let list = try JSONDecoder().decode(GmailMessageList.self, from: data)

        // Fetch each message's metadata concurrently rather than one at a time —
        // sequential requests here would mean up to `maxResults` serial round
        // trips before returning a single list/search call.
        let refs = list.messages ?? []
        let summaries = try await withThrowingTaskGroup(of: (Int, EmailSummary).self) { group in
            for (index, ref) in refs.enumerated() {
                group.addTask {
                    let summary = try await fetchSummary(id: ref.id, token: token)
                    return (index, summary)
                }
            }
            var indexed: [(Int, EmailSummary)] = []
            for try await result in group {
                indexed.append(result)
            }
            return indexed.sorted { $0.0 < $1.0 }.map(\.1)
        }

        return EmailPage(messages: summaries, nextPageToken: list.nextPageToken)
    }

    private func fetchSummary(id: String, token: String) async throws -> EmailSummary {
        var metaComponents = URLComponents(
            url: Self.baseURL.appendingPathComponent("messages/\(id)"),
            resolvingAgainstBaseURL: false
        )!
        metaComponents.queryItems = [
            URLQueryItem(name: "format", value: "metadata"),
            URLQueryItem(name: "metadataHeaders", value: "Subject"),
            URLQueryItem(name: "metadataHeaders", value: "From"),
            URLQueryItem(name: "metadataHeaders", value: "Date"),
        ]
        let metaData = try await get(metaComponents.url!, token: token)
        let meta = try JSONDecoder().decode(GmailMessage.self, from: metaData)
        return EmailSummary(
            id: meta.id,
            threadID: meta.threadId,
            from: meta.header("From") ?? "",
            subject: meta.header("Subject") ?? "",
            snippet: meta.snippet ?? "",
            date: meta.header("Date") ?? ""
        )
    }

    private func send(raw: String, token: String, threadID: String? = nil) async throws -> String {
        var request = URLRequest(url: Self.baseURL.appendingPathComponent("messages/send"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["raw": Data(raw.utf8).base64URLEncodedString()]
        if let threadID {
            body["threadId"] = threadID
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200 ... 299).contains(http.statusCode)
        else {
            let status = (response as? HTTPURLResponse)?.statusCode
            throw EmailProviderError.requestFailed(Self.errorMessage(
                status: status,
                context: "send"
            ))
        }
        let sent = try JSONDecoder().decode(GmailSendResponse.self, from: data)
        return sent.id
    }

    private func get(_ url: URL, token: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw EmailProviderError.requestFailed("No response")
        }
        guard (200 ... 299).contains(http.statusCode) else {
            if http.statusCode == 404 { throw EmailProviderError.notFound }
            throw EmailProviderError.requestFailed(Self.errorMessage(
                status: http.statusCode,
                context: "read"
            ))
        }
        return data
    }

    /// Maps common Gmail error statuses to a message that tells the agent (and
    /// through it, the user) *why* the call failed — most commonly that the
    /// connected account didn't grant the scope this action needs.
    private static func errorMessage(status: Int?, context: String) -> String {
        switch status {
        case 401:
            "Gmail rejected the request as unauthorized — ask the user to reconnect Google in the Eigin app, then try again."
        case 403:
            "Gmail denied this \(context) action — the connected account likely didn't grant the scope required for it. Reconnect the integration in the Eigin app and approve the requested permissions to fix this."
        case .some(let code):
            "Gmail returned \(code) for this \(context) action."
        case nil:
            "Gmail request failed with no response."
        }
    }

    /// Builds a minimal plain-text RFC 822 message, base64url-encoded for the `raw` field.
    private static func buildRFC822(
        to: [String],
        cc: [String],
        subject: String,
        body: String,
        inReplyTo: String? = nil,
        threadID: String? = nil
    ) -> String {
        var lines = [
            "To: \(to.joined(separator: ", "))",
        ]
        if !cc.isEmpty {
            lines.append("Cc: \(cc.joined(separator: ", "))")
        }
        lines.append("Subject: \(subject)")
        lines.append("Content-Type: text/plain; charset=UTF-8")
        if let inReplyTo {
            lines.append("In-Reply-To: <\(inReplyTo)>")
            lines.append("References: <\(inReplyTo)>")
        }
        lines.append("")
        lines.append(body)
        return lines.joined(separator: "\r\n")
    }
}

// MARK: - Wire Models

private struct GmailMessageList: Decodable {
    let messages: [GmailMessageRef]?
    let nextPageToken: String?

    struct GmailMessageRef: Decodable {
        let id: String
        let threadId: String
    }
}

private struct GmailSendResponse: Decodable {
    let id: String
}

private struct GmailMessage: Decodable {
    let id: String
    let threadId: String
    let snippet: String?
    let payload: GmailPayload?

    struct GmailPayload: Decodable {
        let headers: [GmailHeader]?
        let body: GmailBody?
        let parts: [GmailPayload]?
        let mimeType: String?
    }

    struct GmailHeader: Decodable {
        let name: String
        let value: String
    }

    struct GmailBody: Decodable {
        let data: String?
    }

    func header(_ name: String) -> String? {
        payload?.headers?.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    /// Extracts the first `text/plain` part's decoded body, recursing into multipart payloads.
    private func plainTextBody() -> String? {
        guard let payload else { return nil }
        return Self.findPlainText(in: payload)
    }

    private static func findPlainText(in payload: GmailPayload) -> String? {
        if payload.mimeType == "text/plain", let data = payload.body?.data {
            return decodeBase64URL(data)
        }
        for part in payload.parts ?? [] {
            if let found = findPlainText(in: part) {
                return found
            }
        }
        return nil
    }

    private static func decodeBase64URL(_ value: String) -> String? {
        var base64 = value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 {
            base64 += "="
        }
        guard let data = Data(base64Encoded: base64) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func toEmailMessage() -> EmailMessage {
        EmailMessage(
            id: id,
            threadID: threadId,
            from: header("From") ?? "",
            to: (header("To") ?? "").split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) },
            subject: header("Subject") ?? "",
            body: plainTextBody() ?? snippet ?? "",
            date: header("Date") ?? ""
        )
    }
}
