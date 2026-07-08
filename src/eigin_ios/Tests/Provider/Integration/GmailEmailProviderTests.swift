@testable import Eigin
import Foundation
import Testing

/// Verifies ``GmailEmailProvider`` request shape and response mapping against
/// the Gmail REST API, using a fake `URLSession` — no live network calls.
@Suite("GmailEmailProvider")
struct GmailEmailProviderTests {
    private static let base = "https://gmail.googleapis.com/gmail/v1/users/me"

    private func makeProvider(session: URLSession) -> GmailEmailProvider {
        GmailEmailProvider(
            integrationID: UUID(),
            oauthService: FakeIntegrationOAuthService(),
            oauthConfig: PKCEOAuthConfig(
                authorizationEndpoint: URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
                tokenEndpoint: URL(string: "https://oauth2.googleapis.com/token")!,
                clientID: "client-123"
            ),
            urlSession: session
        )
    }

    @Test func listEmailsFetchesMessagesThenMetadataForEach() async throws {
        let session = FakeURLProtocol.fakeSession()
        FakeURLProtocol.stubResponse(
            for: "\(Self.base)/messages?maxResults=10",
            data: Data(#"{"messages":[{"id":"m1","threadId":"t1"}]}"#.utf8),
            statusCode: 200
        )
        FakeURLProtocol.stubResponse(
            for: "\(Self.base)/messages/m1?format=metadata&metadataHeaders=Subject&metadataHeaders=From&metadataHeaders=Date",
            data: Data("""
            {
              "id": "m1",
              "threadId": "t1",
              "snippet": "hello there",
              "payload": {
                "headers": [
                  {"name": "Subject", "value": "Hi"},
                  {"name": "From", "value": "alice@example.com"},
                  {"name": "Date", "value": "2026-01-01"}
                ]
              }
            }
            """.utf8),
            statusCode: 200
        )

        let provider = makeProvider(session: session)
        let page = try await provider.listEmails(maxResults: 10, pageToken: nil)

        #expect(page.messages.count == 1)
        #expect(page.messages[0].id == "m1")
        #expect(page.messages[0].from == "alice@example.com")
        #expect(page.messages[0].subject == "Hi")
        #expect(page.messages[0].snippet == "hello there")
        #expect(page.nextPageToken == nil)
    }

    @Test func listEmailsCarriesNextPageTokenAndForwardsItOnTheNextCall() async throws {
        let session = FakeURLProtocol.fakeSession()
        FakeURLProtocol.stubResponse(
            for: "\(Self.base)/messages?maxResults=10",
            data: Data(#"{"messages":[],"nextPageToken":"page-2"}"#.utf8),
            statusCode: 200
        )
        FakeURLProtocol.stubResponse(
            for: "\(Self.base)/messages?maxResults=10&pageToken=page-2",
            data: Data(#"{"messages":[]}"#.utf8),
            statusCode: 200
        )

        let provider = makeProvider(session: session)
        let firstPage = try await provider.listEmails(maxResults: 10, pageToken: nil)
        #expect(firstPage.nextPageToken == "page-2")

        let secondPage = try await provider.listEmails(maxResults: 10, pageToken: "page-2")
        #expect(secondPage.nextPageToken == nil)
    }

    @Test func searchEmailsIncludesQueryParam() async throws {
        let session = FakeURLProtocol.fakeSession()
        FakeURLProtocol.stubResponse(
            for: "\(Self.base)/messages?maxResults=5&q=from:alice",
            data: Data(#"{"messages":[]}"#.utf8),
            statusCode: 200
        )

        let provider = makeProvider(session: session)
        let page = try await provider.searchEmails(
            query: "from:alice",
            maxResults: 5,
            pageToken: nil
        )

        #expect(page.messages.isEmpty)
    }

    @Test func readEmailDecodesPlainTextBody() async throws {
        let session = FakeURLProtocol.fakeSession()
        let encodedBody = Data("Hello from Gmail".utf8).base64URLEncodedString()
        FakeURLProtocol.stubResponse(
            for: "\(Self.base)/messages/m1?format=full",
            data: Data("""
            {
              "id": "m1",
              "threadId": "t1",
              "snippet": "Hello from…",
              "payload": {
                "mimeType": "text/plain",
                "headers": [
                  {"name": "Subject", "value": "Hi"},
                  {"name": "From", "value": "alice@example.com"},
                  {"name": "To", "value": "me@example.com"},
                  {"name": "Date", "value": "2026-01-01"}
                ],
                "body": {"data": "\(encodedBody)"}
              }
            }
            """.utf8),
            statusCode: 200
        )

        let provider = makeProvider(session: session)
        let message = try await provider.readEmail(id: "m1")

        #expect(message.subject == "Hi")
        #expect(message.from == "alice@example.com")
        #expect(message.to == ["me@example.com"])
        #expect(message.body == "Hello from Gmail")
    }

    @Test func sendEmailPostsBase64EncodedRFC822Message() async throws {
        let session = FakeURLProtocol.fakeSession()
        FakeURLProtocol.stubResponse(
            for: "\(Self.base)/messages/send",
            data: Data(#"{"id":"sent-1"}"#.utf8),
            statusCode: 200
        )
        FakeURLProtocol.stubResponse(
            for: "\(Self.base)/messages/sent-1?format=full",
            data: Data(#"{"id":"sent-1","threadId":"t1","payload":{"headers":[]}}"#.utf8),
            statusCode: 200
        )

        let provider = makeProvider(session: session)
        let sent = try await provider.sendEmail(
            to: ["bob@example.com"], cc: [], subject: "Hi", body: "Body text"
        )

        #expect(sent.id == "sent-1")
        let body = try #require(FakeURLProtocol.lastRequestBody(for: "\(Self.base)/messages/send"))
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        let raw = try #require(json?["raw"] as? String)
        #expect(!raw.contains("+"))
        #expect(!raw.contains("/"))
    }

    @Test func replyEmailReadsOriginalThenSendsWithReferences() async throws {
        let session = FakeURLProtocol.fakeSession()
        FakeURLProtocol.stubResponse(
            for: "\(Self.base)/messages/m1?format=full",
            data: Data("""
            {
              "id": "m1",
              "threadId": "t1",
              "snippet": "hi",
              "payload": {
                "headers": [
                  {"name": "Subject", "value": "Original"},
                  {"name": "From", "value": "alice@example.com"}
                ]
              }
            }
            """.utf8),
            statusCode: 200
        )
        FakeURLProtocol.stubResponse(
            for: "\(Self.base)/messages/send",
            data: Data(#"{"id":"reply-1"}"#.utf8),
            statusCode: 200
        )
        FakeURLProtocol.stubResponse(
            for: "\(Self.base)/messages/reply-1?format=full",
            data: Data(#"{"id":"reply-1","threadId":"t1","payload":{"headers":[]}}"#.utf8),
            statusCode: 200
        )

        let provider = makeProvider(session: session)
        let sent = try await provider.replyEmail(messageID: "m1", body: "Thanks!")

        #expect(sent.id == "reply-1")
        let body = try #require(FakeURLProtocol.lastRequestBody(for: "\(Self.base)/messages/send"))
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        #expect(json?["threadId"] as? String == "t1")
    }
}
