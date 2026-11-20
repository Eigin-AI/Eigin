@testable import Eigin
import Foundation
import Testing

@Suite("Attachment download")
struct AttachmentDownloadTests {
    @Test func rejectsOversizedBodyWithoutContentLength() async throws {
        let url = try #require(URL(string: "https://example.com/attachment-\(UUID())"))
        let session = FakeURLProtocol.fakeSession()
        FakeURLProtocol.stubResponse(
            for: url.absoluteString,
            data: Data(repeating: 65, count: 1025),
            statusCode: 200
        )
        await #expect(throws: EmailProviderError.self) {
            try await AttachmentDownload.get(
                url,
                token: "test",
                session: session,
                deadline: Date().addingTimeInterval(5),
                limit: 1024
            )
        }
    }

    @Test func allowsExactLimitAndRejectsExpiredDeadline() async throws {
        let url = try #require(URL(string: "https://example.com/attachment-\(UUID())"))
        let session = FakeURLProtocol.fakeSession()
        FakeURLProtocol.stubResponse(
            for: url.absoluteString,
            data: Data(repeating: 65, count: 1024),
            statusCode: 200
        )
        let result = try await AttachmentDownload.get(
            url,
            token: "test",
            session: session,
            deadline: Date().addingTimeInterval(5),
            limit: 1024
        )
        #expect(result.count == 1024)
        await #expect(throws: URLError.self) {
            try await AttachmentDownload.get(
                url,
                token: "test",
                session: session,
                deadline: .distantPast
            )
        }
    }

    @Test func absoluteDeadlineStopsTricklingResponse() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FakeAttachmentStreamURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let start = Date()
        await #expect(throws: URLError.self) {
            try await AttachmentDownload.get(
                #require(URL(string: "https://example.com/trickle")),
                token: "test",
                session: session,
                deadline: start.addingTimeInterval(0.2)
            )
        }
        #expect(Date().timeIntervalSince(start) < 1.5)
    }

    @Test func absoluteDeadlineIncludesWaitingForHeaders() async throws {
        let url = try #require(URL(string: "https://example.com/attachment-\(UUID())"))
        let session = FakeURLProtocol.fakeSession()
        FakeURLProtocol.stubResponse(for: url.absoluteString, data: Data([65]), statusCode: 200)
        FakeURLProtocol.stubDelay(for: url.absoluteString, seconds: 2)
        let start = Date()
        await #expect(throws: URLError.self) {
            try await AttachmentDownload.get(
                url,
                token: "test",
                session: session,
                deadline: start.addingTimeInterval(0.2)
            )
        }
        #expect(Date().timeIntervalSince(start) < 1.5)
    }
}
