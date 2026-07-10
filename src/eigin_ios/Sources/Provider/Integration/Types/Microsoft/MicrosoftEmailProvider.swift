import Foundation

/// An ``EmailProvider`` backend for Microsoft Graph mail (personal Hotmail/
/// outlook.com/live.dk accounts via the `/consumers` authority).
///
/// Sends and replies through Graph's `sendMail`/`reply` actions, which send
/// immediately in one call and return `202` with no body — there's nothing to
/// read back. Creating a draft first would give us a real id to read back,
/// but drafting (`POST /me/messages`, `createReply`) requires the
/// `Mail.ReadWrite` permission, a much broader grant (it also allows deleting
/// and moving mail) than the `Mail.Read`/`Mail.Send` split this integration
/// is scoped to, mirroring ``GmailEmailProvider``'s read/send-only grant. So
/// `sendEmail`/`replyEmail` synthesize the returned ``EmailMessage`` from what
/// was actually submitted instead: it still lets the agent keep the content
/// it just committed to (the contract's stated purpose), just without a real
/// server-issued id — a message just sent this way can't be looked up again
/// by ``readEmail(id:)``.
struct MicrosoftEmailProvider: EmailProvider {
    let integrationID: UUID
    let oauthService: any IntegrationOAuthService
    let oauthConfig: PKCEOAuthConfig
    /// The connected mailbox's own address, used to fill in `from` on
    /// synthesized sent/reply messages (Graph's send actions don't return one).
    let accountAddress: String
    let urlSession: URLSession

    private static let baseURL = URL(string: "https://graph.microsoft.com/v1.0/me")!
    private static let summarySelect = "id,conversationId,subject,bodyPreview,from,receivedDateTime"
    private static let messageSelect = "id,conversationId,subject,from,toRecipients,receivedDateTime,body"
    private static let plainTextBodyHeader = ["Prefer": #"outlook.body-content-type="text""#]

    init(
        integrationID: UUID,
        oauthService: any IntegrationOAuthService,
        oauthConfig: PKCEOAuthConfig,
        accountAddress: String,
        urlSession: URLSession = .shared
    ) {
        self.integrationID = integrationID
        self.oauthService = oauthService
        self.oauthConfig = oauthConfig
        self.accountAddress = accountAddress
        self.urlSession = urlSession
    }

    // MARK: - EmailProvider

    func listEmails(maxResults: Int, pageToken: String?) async throws -> EmailPage {
        try await fetchPage(searchQuery: nil, maxResults: maxResults, pageToken: pageToken)
    }

    func searchEmails(
        query: String,
        maxResults: Int,
        pageToken: String?
    ) async throws -> EmailPage {
        try await fetchPage(searchQuery: query, maxResults: maxResults, pageToken: pageToken)
    }

    func readEmail(id: String) async throws -> EmailMessage {
        let token = try await accessToken()
        let data = try await get(readURL(id: id), token: token, headers: Self.plainTextBodyHeader)
        return try data.decoded(GraphMessage.self).toEmailMessage()
    }

    func sendEmail(
        to: [String],
        cc: [String],
        subject: String,
        body: String
    ) async throws -> EmailMessage {
        let token = try await accessToken()
        try await post(
            url: Self.baseURL.appendingPathComponent("sendMail"),
            body: [
                "message": [
                    "subject": subject,
                    "body": ["contentType": "Text", "content": body],
                    "toRecipients": Self.recipients(to),
                    "ccRecipients": Self.recipients(cc),
                ],
            ],
            token: token,
            context: "send"
        )
        // No id: sendMail returns 202 with no body, so there's nothing to
        // read back. See the type-level doc comment for why.
        return EmailMessage(
            id: "", threadID: "", from: accountAddress, to: to, subject: subject, body: body,
            date: Self.now()
        )
    }

    func replyEmail(messageID: String, body: String) async throws -> EmailMessage {
        let original = try await readEmail(id: messageID)
        let token = try await accessToken()
        try await post(
            url: Self.baseURL.appendingPathComponent("messages/\(messageID)/reply"),
            body: ["comment": body],
            token: token,
            context: "reply"
        )
        let subject = original.subject.hasPrefix("Re:") ? original.subject : "Re: \(original.subject)"
        return EmailMessage(
            id: "", threadID: original.threadID, from: accountAddress, to: [original.from],
            subject: subject, body: body, date: Self.now()
        )
    }

    // MARK: - Private

    private func accessToken() async throws -> String {
        guard let token = try await oauthService.validToken(
            config: oauthConfig,
            integrationID: integrationID
        ) else {
            throw EmailProviderError.notAuthenticated
        }
        return token
    }

    private func fetchPage(
        searchQuery: String?,
        maxResults: Int,
        pageToken: String?
    ) async throws -> EmailPage {
        let token = try await accessToken()

        // A page token is the previous response's full `@odata.nextLink` URL,
        // which already encodes $top/$search/$skip — reuse it verbatim rather
        // than rebuilding the query.
        let url: URL
        if let pageToken, let nextURL = URL(string: pageToken) {
            url = nextURL
        } else {
            var components = URLComponents(
                url: Self.baseURL.appendingPathComponent("messages"),
                resolvingAgainstBaseURL: false
            )!
            var items = [
                URLQueryItem(name: "$top", value: "\(maxResults)"),
                URLQueryItem(name: "$select", value: Self.summarySelect),
            ]
            if let searchQuery {
                // Graph's $search on /me/messages (unlike its work/school-only
                // Search API) supports personal accounts; the query is
                // forwarded as KQL verbatim, so its syntax differs from
                // Gmail's `q` operators.
                items.append(URLQueryItem(name: "$search", value: "\"\(searchQuery)\""))
            }
            components.queryItems = items
            url = components.url!
        }

        let list = try await get(url, token: token).decoded(GraphMessageList.self)
        return EmailPage(
            messages: list.value.map { $0.toEmailSummary() },
            nextPageToken: list.nextLink
        )
    }

    private func post(
        url: URL,
        body: [String: Any],
        token: String,
        context: String
    ) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200 ... 299).contains(http.statusCode)
        else {
            throw EmailProviderError.requestFailed(Self.errorMessage(
                status: (response as? HTTPURLResponse)?.statusCode,
                context: context
            ))
        }
    }

    private func get(
        _ url: URL,
        token: String,
        headers: [String: String] = [:]
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
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

    private func readURL(id: String) -> URL {
        var components = URLComponents(
            url: Self.baseURL.appendingPathComponent("messages/\(id)"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "$select", value: Self.messageSelect)]
        return components.url!
    }

    private static func recipients(_ addresses: [String]) -> [[String: Any]] {
        addresses.map { ["emailAddress": ["address": $0]] }
    }

    private static func now() -> String {
        ISO8601DateFormatter().string(from: .now)
    }

    /// Maps common Graph error statuses to a message that tells the agent
    /// (and through it, the user) *why* the call failed — most commonly that
    /// the connected account didn't grant the scope this action needs.
    private static func errorMessage(status: Int?, context: String) -> String {
        switch status {
        case 401:
            "Microsoft rejected the request as unauthorized — the connection may need to be re-authorized."
        case 403:
            "Microsoft denied this \(context) action — the connected account likely didn't grant the scope required for it. Reconnect the integration and approve all requested permissions to fix this."
        case .some(let code):
            "Microsoft returned \(code) for this \(context) action."
        case nil:
            "Microsoft request failed with no response."
        }
    }
}

// MARK: - Wire Models

private extension Data {
    func decoded<T: Decodable>(_ type: T.Type) throws -> T {
        try JSONDecoder().decode(type, from: self)
    }
}

private struct GraphMessageList: Decodable {
    let value: [GraphMessage]
    let nextLink: String?

    enum CodingKeys: String, CodingKey {
        case value
        case nextLink = "@odata.nextLink"
    }
}

private struct GraphMessage: Decodable {
    let id: String
    let conversationId: String?
    let subject: String?
    let bodyPreview: String?
    let from: GraphRecipient?
    let toRecipients: [GraphRecipient]?
    let receivedDateTime: String?
    let body: GraphBody?

    struct GraphRecipient: Decodable {
        let emailAddress: GraphEmailAddress?
    }

    struct GraphEmailAddress: Decodable {
        let address: String?
    }

    struct GraphBody: Decodable {
        let content: String?
    }

    func toEmailSummary() -> EmailSummary {
        EmailSummary(
            id: id,
            threadID: conversationId ?? id,
            from: from?.emailAddress?.address ?? "",
            subject: subject ?? "",
            snippet: bodyPreview ?? "",
            date: receivedDateTime ?? ""
        )
    }

    func toEmailMessage() -> EmailMessage {
        EmailMessage(
            id: id,
            threadID: conversationId ?? id,
            from: from?.emailAddress?.address ?? "",
            to: (toRecipients ?? []).compactMap { $0.emailAddress?.address },
            subject: subject ?? "",
            body: body?.content ?? bodyPreview ?? "",
            date: receivedDateTime ?? ""
        )
    }
}
