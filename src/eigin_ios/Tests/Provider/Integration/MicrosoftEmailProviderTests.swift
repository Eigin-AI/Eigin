@testable import Eigin
import Foundation
import Testing

/// Verifies ``MicrosoftEmailProvider`` request shape and response mapping
/// against Microsoft Graph, using a fake `URLSession` — no live network calls.
@Suite("MicrosoftEmailProvider")
struct MicrosoftEmailProviderTests {
    private static let base = "https://graph.microsoft.com/v1.0/me"
    private static let summarySelect =
        "id,conversationId,subject,bodyPreview,from,receivedDateTime"
    private static let messageSelect =
        "id,conversationId,subject,from,toRecipients,receivedDateTime,body"

    private func makeProvider(
        session: URLSession,
        accountAddress: String = "me@outlook.com"
    ) -> MicrosoftEmailProvider {
        MicrosoftEmailProvider(
            integrationID: UUID(),
            oauthService: FakeIntegrationOAuthService(),
            oauthConfig: PKCEOAuthConfig(
                authorizationEndpoint: URL(
                    string: "https://login.microsoftonline.com/consumers/oauth2/v2.0/authorize"
                )!,
                tokenEndpoint: URL(
                    string: "https://login.microsoftonline.com/consumers/oauth2/v2.0/token"
                )!,
                clientID: "client-123"
            ),
            accountAddress: accountAddress,
            urlSession: session
        )
    }

    @Test func listEmailsFetchesAllSummariesInOneCall() async throws {
        let session = FakeURLProtocol.fakeSession()
        FakeURLProtocol.stubResponse(
            for: "\(Self.base)/messages?$top=10&$select=\(Self.summarySelect)",
            data: Data("""
            {
              "value": [
                {
                  "id": "m1",
                  "conversationId": "t1",
                  "subject": "Hi",
                  "bodyPreview": "hello there",
                  "from": {"emailAddress": {"address": "alice@outlook.com"}},
                  "receivedDateTime": "2026-01-01T00:00:00Z"
                }
              ]
            }
            """.utf8),
            statusCode: 200
        )

        let provider = makeProvider(session: session)
        let page = try await provider.listEmails(maxResults: 10, pageToken: nil)

        #expect(page.messages.count == 1)
        #expect(page.messages[0].id == "m1")
        #expect(page.messages[0].threadID == "t1")
        #expect(page.messages[0].from == "alice@outlook.com")
        #expect(page.messages[0].subject == "Hi")
        #expect(page.messages[0].snippet == "hello there")
        #expect(page.nextPageToken == nil)
    }

    @Test func listEmailsCarriesNextLinkAndForwardsItVerbatimOnTheNextCall() async throws {
        let session = FakeURLProtocol.fakeSession()
        let nextLink = "\(Self.base)/messages?$top=10&$select=\(Self.summarySelect)&$skip=10"
        FakeURLProtocol.stubResponse(
            for: "\(Self.base)/messages?$top=10&$select=\(Self.summarySelect)",
            data: Data("{\"value\":[],\"@odata.nextLink\":\"\(nextLink)\"}".utf8),
            statusCode: 200
        )
        FakeURLProtocol.stubResponse(
            for: nextLink,
            data: Data(#"{"value":[]}"#.utf8),
            statusCode: 200
        )

        let provider = makeProvider(session: session)
        let firstPage = try await provider.listEmails(maxResults: 10, pageToken: nil)
        #expect(firstPage.nextPageToken == nextLink)

        let secondPage = try await provider.listEmails(
            maxResults: 10,
            pageToken: firstPage.nextPageToken
        )
        #expect(secondPage.nextPageToken == nil)
    }

    @Test func searchEmailsIncludesQuotedSearchParam() async throws {
        let session = FakeURLProtocol.fakeSession()
        FakeURLProtocol.stubResponse(
            for: "\(Self.base)/messages?$top=5&$select=\(Self.summarySelect)&$search=%22invoice%22",
            data: Data(#"{"value":[]}"#.utf8),
            statusCode: 200
        )

        let provider = makeProvider(session: session)
        let page = try await provider.searchEmails(query: "invoice", maxResults: 5, pageToken: nil)

        #expect(page.messages.isEmpty)
    }

    @Test func readEmailDecodesPlainTextBody() async throws {
        let session = FakeURLProtocol.fakeSession()
        FakeURLProtocol.stubResponse(
            for: "\(Self.base)/messages/m1?$select=\(Self.messageSelect)",
            data: Data("""
            {
              "id": "m1",
              "conversationId": "t1",
              "subject": "Hi",
              "from": {"emailAddress": {"address": "alice@outlook.com"}},
              "toRecipients": [{"emailAddress": {"address": "me@outlook.com"}}],
              "receivedDateTime": "2026-01-01T00:00:00Z",
              "body": {"contentType": "text", "content": "Hello from Graph"}
            }
            """.utf8),
            statusCode: 200
        )

        let provider = makeProvider(session: session)
        let message = try await provider.readEmail(id: "m1")

        #expect(message.subject == "Hi")
        #expect(message.from == "alice@outlook.com")
        #expect(message.to == ["me@outlook.com"])
        #expect(message.body == "Hello from Graph")
        #expect(message.threadID == "t1")
    }

    @Test func sendEmailPostsToSendMailAndSynthesizesTheSentMessage() async throws {
        let session = FakeURLProtocol.fakeSession()
        FakeURLProtocol.stubResponse(
            for: "\(Self.base)/sendMail",
            data: Data(),
            statusCode: 202
        )

        let provider = makeProvider(session: session, accountAddress: "me@outlook.com")
        let sent = try await provider.sendEmail(
            to: ["bob@example.com"], cc: [], subject: "Hi", body: "Body text"
        )

        // No real id: sendMail is fire-and-forget, so this is synthesized from
        // what was submitted rather than read back from the server.
        #expect(sent.id.isEmpty)
        #expect(sent.from == "me@outlook.com")
        #expect(sent.to == ["bob@example.com"])
        #expect(sent.subject == "Hi")
        #expect(sent.body == "Body text")

        let requestBody = try #require(FakeURLProtocol
            .lastRequestBody(for: "\(Self.base)/sendMail"))
        let json = try JSONSerialization.jsonObject(with: requestBody) as? [String: Any]
        let message = try #require(json?["message"] as? [String: Any])
        #expect(message["subject"] as? String == "Hi")
        let to = try #require(message["toRecipients"] as? [[String: Any]])
        let toAddress = (to.first?["emailAddress"] as? [String: Any])?["address"] as? String
        #expect(toAddress == "bob@example.com")
    }

    @Test func replyEmailReadsOriginalThenPostsCommentToTheReplyAction() async throws {
        let session = FakeURLProtocol.fakeSession()
        FakeURLProtocol.stubResponse(
            for: "\(Self.base)/messages/m1?$select=\(Self.messageSelect)",
            data: Data("""
            {
              "id": "m1",
              "conversationId": "t1",
              "subject": "Original",
              "from": {"emailAddress": {"address": "alice@outlook.com"}},
              "receivedDateTime": "2026-01-01T00:00:00Z",
              "body": {"contentType": "text", "content": "hi"}
            }
            """.utf8),
            statusCode: 200
        )
        FakeURLProtocol.stubResponse(
            for: "\(Self.base)/messages/m1/reply",
            data: Data(),
            statusCode: 202
        )

        let provider = makeProvider(session: session, accountAddress: "me@outlook.com")
        let sent = try await provider.replyEmail(messageID: "m1", body: "Thanks!")

        // No real id, same reason as sendEmail — the reply action doesn't
        // return one either. threadID/from/to come from the original message
        // and the connected account, not the server response.
        #expect(sent.id.isEmpty)
        #expect(sent.threadID == "t1")
        #expect(sent.from == "me@outlook.com")
        #expect(sent.to == ["alice@outlook.com"])
        #expect(sent.subject == "Re: Original")
        #expect(sent.body == "Thanks!")

        let requestBody = try #require(
            FakeURLProtocol.lastRequestBody(for: "\(Self.base)/messages/m1/reply")
        )
        let json = try JSONSerialization.jsonObject(with: requestBody) as? [String: Any]
        #expect(json?["comment"] as? String == "Thanks!")
    }
}
