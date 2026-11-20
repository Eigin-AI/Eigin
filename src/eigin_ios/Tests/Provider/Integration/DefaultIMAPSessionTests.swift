@testable import Eigin
import Foundation
import SwiftMail
import Testing

@Suite("Default IMAP session", .serialized)
struct DefaultIMAPSessionTests {
    @Test func inlineHTMLContentIDRemainsTheBody() async throws {
        let body = "<p>Invoice =E6=F8=E5</p>"
        let server = try FixtureIMAPServer(
            structure: #"("TEXT" "HTML" ("CHARSET" "ISO-8859-1") "<body-id>" NIL "QUOTED-PRINTABLE" 24 1 NIL ("INLINE" NIL) NIL NIL)"#,
            bodies: ["1": Data(body.utf8)]
        )
        let message = try await read(server)
        #expect(message.body == "Invoice æøå")
        #expect(message.attachments.isEmpty)
        #expect(server.fetchedSections == ["1"])
    }

    @Test func attachedMessageDescendantsAreNeverFetchedAsBody() async throws {
        let envelope = #"(NIL "Attached invoice" NIL NIL NIL NIL NIL NIL NIL NIL)"#
        let inner = #"("TEXT" "PLAIN" ("CHARSET" "UTF-8") NIL NIL "7BIT" 12 1)"#
        let outer = #"("TEXT" "HTML" ("CHARSET" "UTF-8") NIL NIL "BASE64" 32 1)"#
        let attached = "(\"MESSAGE\" \"RFC822\" NIL NIL NIL \"7BIT\" 400 \(envelope) \(inner) 10 NIL (\"ATTACHMENT\" (\"FILENAME\" \"invoice.eml\")) NIL NIL)"
        let server = try FixtureIMAPServer(
            structure: "(\(outer) \(attached) \"MIXED\")",
            bodies: [
                "1": Data(Data("<p>Outer body æøå</p>".utf8).base64EncodedString().utf8),
                "2.1": Data("Attached text".utf8),
            ]
        )
        let message = try await read(server)
        #expect(message.body == "Outer body æøå")
        #expect(server.fetchedSections == ["1"])
        #expect(message.attachments.map(\.filename) == ["invoice.eml"])
        #expect(message.attachments.allSatisfy { !$0.readable })
    }

    @Test func namedTextAttachmentIsExcludedEvenWithContentID() async throws {
        let body = #"("TEXT" "PLAIN" ("CHARSET" "UTF-8") NIL NIL "7BIT" 10 1)"#
        let attachment = #"("TEXT" "PLAIN" ("CHARSET" "UTF-8" "NAME" "invoice.txt") "<file-id>" NIL "7BIT" 12 1 NIL ("INLINE" NIL) NIL NIL)"#
        let server = try FixtureIMAPServer(
            structure: "(\(body) \(attachment) \"MIXED\")",
            bodies: ["1": Data("Outer body".utf8), "2": Data("File content".utf8)]
        )
        let message = try await read(server)
        #expect(message.body == "Outer body")
        #expect(server.fetchedSections == ["1"])
        #expect(message.attachments.map(\.filename) == ["invoice.txt"])
    }

    @Test func explicitAttachmentDispositionWinsOverMatchingContentID() async throws {
        let body = #"("TEXT" "PLAIN" NIL NIL NIL "7BIT" 10 1)"#
        let attachment = #"("TEXT" "PLAIN" NIL "<file-id>" NIL "7BIT" 12 1 NIL ("ATTACHMENT" ("FILENAME" "file-id")) NIL NIL)"#
        let server = try FixtureIMAPServer(
            structure: "(\(body) \(attachment) \"MIXED\")",
            bodies: ["1": Data("Outer body".utf8), "2": Data("File content".utf8)]
        )
        let message = try await read(server)
        #expect(message.body == "Outer body")
        #expect(server.fetchedSections == ["1"])
        #expect(message.attachments.map(\.filename) == ["file-id"])
    }

    private func read(_ server: FixtureIMAPServer) async throws -> IMAPFullMessage {
        let port = try await server.start()
        defer { server.stop() }
        let session = DefaultIMAPSession { settings in
            IMAPServer(
                host: settings.imapHost,
                port: settings.imapPort,
                transportSecurity: .plainText
            )
        }
        do {
            try await session.open(settings: IMAPAccountSettings(
                emailAddress: "test@example.com", imapHost: "127.0.0.1", imapPort: Int(port),
                smtpHost: "127.0.0.1", password: "test-only"
            ))
            let message = try await session.fetchMessage(uid: 1)
            await session.close()
            return try #require(message)
        } catch {
            await session.close()
            throw error
        }
    }
}
