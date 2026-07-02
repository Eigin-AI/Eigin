@testable import Eigin
import Testing

@Suite("ChatItem.buildItems with attachments")
struct ChatItemAttachmentTests {
    private func imageAttachment() -> MessageAttachment {
        MessageAttachment(id: UUID(), kind: .image, mimeType: "image/jpeg", byteCount: 1000)
    }

    @MainActor
    private func buildItems(from messages: [ChatMessage]) -> [ChatItem] {
        let loop = AgenticChatLoop(isBootstrap: false)
        return ChatItem.buildItems(from: messages, chatLoop: loop, chatError: nil)
    }

    // MARK: - Tests

    @Test("User message with image produces item carrying attachment")
    @MainActor
    func userMessageWithImage() {
        let att = imageAttachment()
        let msg = ChatMessage(role: "user", content: "Look:", attachments: [att])

        let items = buildItems(from: [msg])

        #expect(items.count == 1)
        if case .message(_, let role, _, let attachments) = items[0] {
            #expect(role == "user")
            #expect(attachments.count == 1)
            #expect(attachments[0].id == att.id)
        } else {
            Issue.record("Expected .message item")
        }
    }

    @Test("Image-only message (nil content) produces item with attachment")
    @MainActor
    func imageOnlyMessage() {
        var msg = ChatMessage(role: "user", content: nil)
        msg.attachments = [imageAttachment()]

        let items = buildItems(from: [msg])

        #expect(items.count == 1)
        if case .message(_, _, let content, let attachments) = items[0] {
            #expect(content.isEmpty)
            #expect(attachments.count == 1)
        } else {
            Issue.record("Expected .message item")
        }
    }

    @Test("Text-only message produces item with empty attachments")
    @MainActor
    func textOnlyMessageHasNoAttachments() {
        let msg = ChatMessage(role: "user", content: "Hello")

        let items = buildItems(from: [msg])

        #expect(items.count == 1)
        if case .message(_, _, _, let attachments) = items[0] {
            #expect(attachments.isEmpty)
        } else {
            Issue.record("Expected .message item")
        }
    }

    @Test("Stripped attachment placeholder still produces a visible item")
    @MainActor
    func strippedAttachmentPlaceholderVisible() {
        // Simulate a message where the attachment was stripped but placeholder remains
        let msg = ChatMessage(role: "user", content: "[image omitted]")

        let items = buildItems(from: [msg])

        #expect(items.count == 1)
        if case .message(_, _, let content, _) = items[0] {
            #expect(content.contains("[image omitted]"))
        }
    }
}
