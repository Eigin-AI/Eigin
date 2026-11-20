@testable import Eigin
import Foundation
import SwiftMail
import Testing

/// Verifies ``GmailEmailProvider`` request shape and response mapping against
/// the Gmail REST API, using a fake `URLSession` — no live network calls.
@Suite("GmailEmailProvider")
struct GmailEmailProviderTests {
    private static let base = "https://gmail.googleapis.com/gmail/v1/users/me"

    private func makeProvider(
        session: URLSession,
        healthMonitor: (any IntegrationHealthReporter)? = nil
    ) -> GmailEmailProvider {
        GmailEmailProvider(
            integrationID: integrationID,
            oauthService: FakeIntegrationOAuthService(),
            oauthConfig: PKCEOAuthConfig(
                authorizationEndpoint: URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
                tokenEndpoint: URL(string: "https://oauth2.googleapis.com/token")!,
                clientID: "client-123"
            ),
            urlSession: session,
            healthMonitor: healthMonitor
        )
    }

    private let integrationID = UUID()

    @Test func discoversNestedAttachmentsAndKeepsTextAttachmentsOutOfBody() async throws {
        let session = FakeURLProtocol.fakeSession()
        FakeURLProtocol.stubResponse(
            for: "\(Self.base)/messages/attachment-mail?format=full",
            data: Data(
                #"{"id":"attachment-mail","threadId":"t","payload":{"mimeType":"multipart/mixed","parts":[{"partId":"0","filename":"invoice.txt","mimeType":"text/plain","body":{"data":"SW52b2ljZSAxMjM","size":11}},{"partId":"1","mimeType":"text/plain","body":{"data":"Qm9keQ"}},{"mimeType":"multipart/mixed","parts":[{"partId":"2.0","filename":"invoice.pdf","mimeType":"application/pdf","body":{"attachmentId":"remote","size":4}}]}]}}"#
                    .utf8
            ),
            statusCode: 200
        )
        FakeURLProtocol.stubResponse(
            for: "\(Self.base)/messages/attachment-mail/attachments/remote",
            data: Data(#"{"data":"JVBERg","size":4}"#.utf8),
            statusCode: 200
        )
        let provider = makeProvider(session: session)
        let message = try await provider.readEmail(id: "attachment-mail")
        #expect(message.body == "Body")
        #expect(message.attachments.map(\.id) == ["part:0", "part:2.0"])
        let inline = try await provider.fetchAttachment(
            messageID: "attachment-mail",
            attachmentID: "part:0"
        )
        #expect(String(data: inline.data, encoding: .utf8) == "Invoice 123")
        let external = try await provider.fetchAttachment(
            messageID: "attachment-mail",
            attachmentID: "part:2.0"
        )
        #expect(external.data == Data("%PDF".utf8))
        await #expect(throws: EmailProviderError.self) {
            try await provider.fetchAttachment(messageID: "attachment-mail", attachmentID: "remote")
        }
    }

    @Test func rejectsMalformedAttachmentEncoding() async throws {
        let session = FakeURLProtocol.fakeSession()
        FakeURLProtocol.stubResponse(
            for: "\(Self.base)/messages/bad-attachment?format=full",
            data: Data(
                #"{"id":"bad-attachment","threadId":"t","payload":{"partId":"0","filename":"invoice.txt","mimeType":"text/plain","body":{"data":"%%%"}}}"#
                    .utf8
            ),
            statusCode: 200
        )
        await #expect(throws: EmailProviderError.self) {
            try await makeProvider(session: session).fetchAttachment(
                messageID: "bad-attachment",
                attachmentID: "part:0"
            )
        }
    }

    @Test func discoversLabels() async throws {
        let session = FakeURLProtocol.fakeSession()
        FakeURLProtocol.stubResponse(
            for: "\(Self.base)/labels",
            data: Data(
                #"{"labels":[{"id":"INBOX","name":"INBOX"},{"id":"Label_1","name":"Work/Receipts"}]}"#
                    .utf8
            ),
            statusCode: 200
        )
        let folders = try await makeProvider(session: session).listFolders()
        #expect(folders == [
            EmailFolder(id: "INBOX", name: "INBOX", parentID: nil),
            EmailFolder(id: "Label_1", name: "Work/Receipts", parentID: nil),
        ])
    }

    @Test(arguments: ["Label_1", "SPAM", "TRASH"])
    func scopesListingAndSearchToLabels(label: String) async throws {
        let session = FakeURLProtocol.fakeSession()
        let flags = label == "Label_1" ? "" : "&includeSpamTrash=true"
        FakeURLProtocol.stubResponse(
            for: "\(Self.base)/messages?maxResults=5&labelIds=\(label)\(flags)",
            data: Data(#"{"messages":[],"nextPageToken":"next"}"#.utf8),
            statusCode: 200
        )
        FakeURLProtocol.stubResponse(
            for: "\(Self.base)/messages?maxResults=5&labelIds=\(label)\(flags)&pageToken=next",
            data: Data(#"{"messages":[]}"#.utf8),
            statusCode: 200
        )
        let provider = makeProvider(session: session)
        let first = try await provider.listEmails(folderID: label, maxResults: 5, pageToken: nil)
        #expect(first.nextPageToken == "next")
        let page = try await provider.listEmails(
            folderID: label,
            maxResults: 5,
            pageToken: first.nextPageToken
        )
        FakeURLProtocol.stubResponse(
            for: "\(Self.base)/messages?maxResults=5&labelIds=\(label)\(flags)&q=invoice",
            data: Data(#"{"messages":[],"nextPageToken":"search-next"}"#.utf8),
            statusCode: 200
        )
        FakeURLProtocol.stubResponse(
            for: "\(Self.base)/messages?maxResults=5&labelIds=\(label)\(flags)&q=invoice&pageToken=search-next",
            data: Data(#"{"messages":[]}"#.utf8),
            statusCode: 200
        )
        let search = try await provider.searchEmails(
            query: "invoice",
            folderID: label,
            maxResults: 5,
            pageToken: nil
        )
        #expect(search.nextPageToken == "search-next")
        let searchNext = try await provider.searchEmails(
            query: "invoice",
            folderID: label,
            maxResults: 5,
            pageToken: search.nextPageToken
        )
        #expect(searchNext.nextPageToken == nil)
        #expect(page.messages.isEmpty)
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
                  {"name": "Subject", "value": "=?UTF-8?B?VGVzdCDigJQgw6bDuMOl?="},
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
        #expect(page.messages[0].subject == "Test — æøå")
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
        let encodedBody = Data("Hello from Gmail — æøå ‘quotes’".utf8).base64URLEncodedString()
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
        #expect(message.body == "Hello from Gmail — æøå ‘quotes’")
    }

    @Test(arguments: [
        "Hi",
        "Test — æøå “quotes”",
        String(repeating: "🐈—æøå ", count: 30),
        String(repeating: "Long ASCII ", count: 20),
    ])
    func sendEmailPostsBase64EncodedRFC822Message(subject: String) async throws {
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
        let bodyText = String(repeating: "Body — æøå ‘quotes’ 🐈\r\n", count: 10)
        let sent = try await provider.sendEmail(
            to: ["bob@example.com"], cc: [], subject: subject, body: bodyText
        )

        #expect(sent.id == "sent-1")
        let body = try #require(FakeURLProtocol.lastRequestBody(for: "\(Self.base)/messages/send"))
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        let raw = try #require(json?["raw"] as? String)
        #expect(!raw.contains("+"))
        #expect(!raw.contains("/"))
        try assertMIME(raw: raw, subject: subject, body: bodyText)
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
                  {"name": "Subject", "value": "Original — æøå"},
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
        let sent = try await provider.replyEmail(messageID: "m1", body: "Thanks — æøå!")

        #expect(sent.id == "reply-1")
        let body = try #require(FakeURLProtocol.lastRequestBody(for: "\(Self.base)/messages/send"))
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        #expect(json?["threadId"] as? String == "t1")
        let raw = try #require(json?["raw"] as? String)
        try assertMIME(raw: raw, subject: "Re: Original — æøå", body: "Thanks — æøå!")
    }

    @Test(arguments: ["UTF-8", "windows-1252", "ISO-8859-1"])
    func readEmailUsesPlainTextPartCharset(charset: String) async throws {
        let text = "Received — æøå ‘quotes’"
        let encoding: String.Encoding = charset == "UTF-8" ? .utf8 :
            (charset == "windows-1252" ? .windowsCP1252 : .isoLatin1)
        let expected = charset == "ISO-8859-1" ? "Received æøå" : text
        let bytes = try #require(expected.data(using: encoding))
        let session = FakeURLProtocol.fakeSession()
        let fixture: [String: Any] = [
            "id": "m1", "threadId": "t1", "snippet": "Fallback",
            "payload": [
                "mimeType": "multipart/alternative",
                "headers": [[
                    "name": "Subject",
                    "value": "=?UTF-8?B?\(Data(text.utf8).base64EncodedString())?=",
                ]],
                "parts": [[
                    "mimeType": "text/plain",
                    "headers": [[
                        "name": "Content-Type",
                        "value": "text/plain; charset=\"\(charset)\"",
                    ]],
                    "body": ["data": bytes.base64URLEncodedString()],
                ]],
            ],
        ]
        try FakeURLProtocol.stubResponse(
            for: "\(Self.base)/messages/m1?format=full",
            data: JSONSerialization.data(withJSONObject: fixture),
            statusCode: 200
        )
        let message = try await makeProvider(session: session).readEmail(id: "m1")
        #expect(message.subject == text)
        #expect(message.body == expected)
    }

    private func assertMIME(raw: String, subject: String, body: String) throws {
        var base64 = raw.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 {
            base64 += "="
        }
        let data = try #require(Data(base64Encoded: base64))
        let message = try #require(String(data: data, encoding: .utf8))
        #expect(message.utf8.allSatisfy { $0 < 128 })
        let sections = message.components(separatedBy: "\r\n\r\n")
        let headers = try #require(sections.first)
        #expect(headers.components(separatedBy: "\r\n").allSatisfy { $0.utf8.count <= 78 })
        if subject.hasPrefix("Re:") {
            #expect(headers.contains("In-Reply-To: <m1>"))
            #expect(headers.contains("References: <m1>"))
        }
        #expect(headers.contains("MIME-Version: 1.0"))
        #expect(headers.contains("Content-Type: text/plain; charset=UTF-8"))
        #expect(headers.contains("Content-Transfer-Encoding: base64"))
        let unfolded = headers.replacingOccurrences(of: "\r\n ", with: " ")
        let subjectLine = try #require(unfolded.components(separatedBy: "\r\n")
            .first { $0.hasPrefix("Subject: ") })
        let subjectValue = String(subjectLine.dropFirst("Subject: ".count))
        #expect(subjectValue.decodeMIMEHeader() == subject)
        if !subjectValue.hasPrefix("=?") {
            #expect(subjectValue == subject)
        }
        let words = subjectValue.hasPrefix("=?") ? subjectValue.components(separatedBy: " ") : []
        var decoded = ""
        for word in words {
            #expect(word.hasPrefix("=?UTF-8?B?"))
            #expect(word.hasSuffix("?="))
            #expect(word.count <= 75)
            let bytes = try #require(Data(base64Encoded: String(word.dropFirst(10).dropLast(2))))
            decoded += try #require(String(data: bytes, encoding: .utf8))
        }
        if !words.isEmpty { #expect(decoded == subject) }
        let encodedBody = try #require(sections.dropFirst().first)
        #expect(encodedBody.components(separatedBy: "\r\n").allSatisfy { $0.count <= 76 })
        let bodyData = try #require(Data(base64Encoded: encodedBody.replacingOccurrences(
            of: "\r\n",
            with: ""
        )))
        #expect(String(data: bodyData, encoding: .utf8) == body)
    }

    @Test func missingTokenFlagsTheIntegrationForReconnect() async throws {
        // The fake session (with a default token) never gets consulted — the
        // service reports no stored token at all.
        let session = FakeURLProtocol.fakeSession()
        let oauth = FakeIntegrationOAuthService()
        oauth.token = nil
        let health = RecordingHealthReporter()
        let provider = try GmailEmailProvider(
            integrationID: integrationID,
            oauthService: oauth,
            oauthConfig: PKCEOAuthConfig(
                authorizationEndpoint: #require(
                    URL(string: "https://accounts.google.com/o/oauth2/v2/auth")
                ),
                tokenEndpoint: #require(URL(string: "https://oauth2.googleapis.com/token")),
                clientID: "client-123"
            ),
            urlSession: session,
            healthMonitor: health
        )

        do {
            _ = try await provider.listEmails(maxResults: 10, pageToken: nil)
            Issue.record("Expected .notAuthenticated")
        } catch let error as EmailProviderError {
            guard case .notAuthenticated = error else {
                Issue.record("Expected .notAuthenticated, got \(error)")
                return
            }
        } catch {
            Issue.record("Expected .notAuthenticated, got \(error)")
        }
        #expect(health.marked == [integrationID])
    }
}
