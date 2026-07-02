@testable import Eigin
import Foundation
import Testing

/// Tests that image attachments are correctly injected into provider wire formats.
@Suite("Image wire conversion")
struct ImageWireConversionTests {
    // MARK: - Helpers

    private func attachment(id: UUID = UUID()) -> MessageAttachment {
        MessageAttachment(
            id: id,
            kind: .image,
            mimeType: "image/jpeg",
            width: 100,
            height: 100,
            byteCount: 512
        )
    }

    /// A minimal store that returns predictable bytes for any ID.
    private final class StubStore: ChatAttachmentStoring, @unchecked Sendable {
        let fixedData: Data
        nonisolated(unsafe) var deletedIDs: [UUID] = []
        /// IDs for which `load`/`loadThumbnail` should simulate a missing file.
        nonisolated(unsafe) var missingIDs: Set<UUID> = []

        init(data: Data = Data("stubimage".utf8)) {
            fixedData = data
        }

        func save(imageData: Data, id: UUID) throws -> MessageAttachment {
            MessageAttachment(
                id: id,
                kind: .image,
                mimeType: "image/jpeg",
                byteCount: imageData.count
            )
        }

        func load(id: UUID) -> Data? {
            missingIDs.contains(id) ? nil : fixedData
        }

        func loadThumbnail(id: UUID) -> Data? {
            missingIDs.contains(id) ? nil : fixedData
        }

        func fileURL(for id: UUID) -> URL? {
            nil
        }

        func delete(id: UUID) {
            deletedIDs.append(id)
        }

        func deleteAll(_ attachments: [MessageAttachment]) {
            attachments.forEach { delete(id: $0.id) }
        }
    }

    // MARK: - ChatCompletionMessage (OpenAI-compatible wire format)

    @Test func wireMessageWithoutAttachmentsEncodesPlainTextContent() throws {
        let message = ChatMessage(role: "user", content: "hello")
        let wire = ChatCompletionMessage(message, store: StubStore())

        let data = try JSONEncoder().encode(wire)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(json["content"] as? String == "hello")
    }

    @Test func wireMessageWithAttachmentsEncodesContentPartsArray() throws {
        let store = StubStore(data: Data("stubimage".utf8))
        let message = ChatMessage(
            role: "user",
            content: "Describe this.",
            attachments: [attachment()]
        )
        let wire = ChatCompletionMessage(message, store: store)

        let data = try JSONEncoder().encode(wire)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let parts = try #require(json["content"] as? [[String: Any]])

        #expect(parts.count == 2)
        #expect(parts[0]["type"] as? String == "text")
        #expect(parts[0]["text"] as? String == "Describe this.")
        #expect(parts[1]["type"] as? String == "image_url")
        let imageURL = try #require(parts[1]["image_url"] as? [String: Any])
        let expectedData = "stubimage".data(using: .utf8)!.base64EncodedString()
        #expect(imageURL["url"] as? String == "data:image/jpeg;base64,\(expectedData)")
        #expect(imageURL["detail"] as? String == "high")
    }

    @Test func wireMessageImageOnlyOmitsTextPart() throws {
        let message = ChatMessage(role: "user", content: nil, attachments: [attachment()])
        let wire = ChatCompletionMessage(message, store: StubStore())

        let data = try JSONEncoder().encode(wire)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let parts = try #require(json["content"] as? [[String: Any]])

        #expect(parts.count == 1)
        #expect(parts[0]["type"] as? String == "image_url")
    }

    @Test func wireMessageKeepsTextPartWhenAttachmentBytesUnavailable() throws {
        // Text alongside an unloadable image: the text part is still included,
        // just without a matching image part (mirrors legacy behavior).
        let att = attachment()
        let store = StubStore()
        store.missingIDs = [att.id]
        let message = ChatMessage(role: "user", content: "hello", attachments: [att])
        let wire = ChatCompletionMessage(message, store: store)

        let data = try JSONEncoder().encode(wire)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let parts = try #require(json["content"] as? [[String: Any]])

        #expect(parts.count == 1)
        #expect(parts[0]["type"] as? String == "text")
        #expect(parts[0]["text"] as? String == "hello")
    }

    @Test func wireMessageOmitsContentWhenImageOnlyAndBytesUnavailable() throws {
        // Image-only message whose bytes can't be loaded: no parts were built,
        // so content falls back to the (nil) plain text and is omitted entirely.
        let att = attachment()
        let store = StubStore()
        store.missingIDs = [att.id]
        let message = ChatMessage(role: "user", content: nil, attachments: [att])
        let wire = ChatCompletionMessage(message, store: store)

        let data = try JSONEncoder().encode(wire)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(json["content"] == nil)
    }

    // MARK: - MessageAttachment encoding (not sent on wire by default)

    @Test func chatMessageEncodingDoesNotIncludeAttachments() throws {
        let id = UUID()
        let msg = ChatMessage(
            role: "user",
            content: "hello",
            attachments: [attachment(id: id)]
        )
        let data = try JSONEncoder().encode(msg)
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        // Attachments must NOT appear in the encoded JSON (they're local-only)
        #expect(dict?["attachments"] == nil)
        #expect(dict?["content"] as? String == "hello")
        #expect(dict?["role"] as? String == "user")
    }

    // MARK: - ChatMessage.withStrippedAttachments

    @Test func withStrippedAttachmentsRemovesAttachmentsAndAppendsPlaceholder() {
        let msg = ChatMessage(role: "user", content: "See this:", attachments: [attachment()])
        let stripped = msg.withStrippedAttachments()

        #expect(stripped.attachments == nil)
        #expect(stripped.content?.contains("[image omitted]") == true)
        #expect(stripped.content?.hasPrefix("See this:") == true)
    }

    @Test func withStrippedAttachmentsNoOpWhenNoAttachments() {
        let msg = ChatMessage(role: "user", content: "plain")
        let result = msg.withStrippedAttachments()
        #expect(result.content == "plain")
        #expect(result.attachments == nil)
    }

    @Test func withStrippedAttachmentsPlaceholderOnlyWhenNoText() {
        var msg = ChatMessage(role: "user", content: nil)
        msg.attachments = [attachment()]
        let stripped = msg.withStrippedAttachments()
        #expect(stripped.content == "[image omitted]")
    }

    // MARK: - MessageAttachment Codable round-trip

    @Test func attachmentCodableRoundTrip() throws {
        let original = attachment()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MessageAttachment.self, from: data)
        #expect(decoded.id == original.id)
        #expect(decoded.mimeType == original.mimeType)
        #expect(decoded.byteCount == original.byteCount)
        #expect(decoded.kind == .image)
    }

    // MARK: - ChatMessage attachments round-trip through Message persistence

    @Test func messagePersistenceRoundTripsAttachments() {
        let att = attachment()
        let chatMsg = ChatMessage(role: "user", content: "hi", attachments: [att])

        // Persist
        let persisted = Message.from(chatMsg)
        #expect(persisted.attachmentsData != nil)

        // Restore
        let restored = persisted.toChatMessage()
        let restoredAttachments = restored.attachments
        #expect(restoredAttachments?.count == 1)
        #expect(restoredAttachments?.first?.id == att.id)
        #expect(restoredAttachments?.first?.mimeType == att.mimeType)
    }

    @Test func messagePersistenceNoAttachmentsIsNil() {
        let chatMsg = ChatMessage(role: "user", content: "hello")
        let persisted = Message.from(chatMsg)
        #expect(persisted.attachmentsData == nil)

        let restored = persisted.toChatMessage()
        #expect(restored.attachments == nil)
    }
}
