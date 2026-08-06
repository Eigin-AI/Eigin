@testable import Eigin
import Foundation
import Testing

@Suite("MessagePipeline.applyImageStripping")
struct ImageStrippingTests {
    // MARK: - Helpers

    private func imageAttachment() -> MessageAttachment {
        MessageAttachment(id: UUID(), kind: .image, mimeType: "image/jpeg", byteCount: 1000)
    }

    private func userWithImage(_ text: String = "look at this") -> ChatMessage {
        ChatMessage(role: "user", content: text, attachments: [imageAttachment()])
    }

    private func user(_ text: String = "hi") -> ChatMessage {
        ChatMessage(role: "user", content: text)
    }

    private func assistant(_ text: String = "ok") -> ChatMessage {
        ChatMessage(role: "assistant", content: text)
    }

    // MARK: - No-op when no attachments

    @Test func passesThrough_noAttachments() {
        let messages = [user(), assistant(), user("more")]
        let result = MessagePipeline.applyImageStripping(messages, supportsVision: true)
        #expect(result.count == 3)
        #expect(result.allSatisfy { $0.attachments == nil })
    }

    // MARK: - Non-vision model strips all images

    @Test func nonVisionStripsAllImages() {
        let messages = [userWithImage("img1"), assistant(), userWithImage("img2")]
        let result = MessagePipeline.applyImageStripping(messages, supportsVision: false)

        // No attachments remain
        #expect(result.allSatisfy { $0.attachments == nil || $0.attachments!.isEmpty })
        // Placeholder appended to content
        let placeholder = MessagePipeline.visionUnsupportedPlaceholder
        #expect(result[0].content?.contains(placeholder) == true)
        #expect(result[2].content?.contains(placeholder) == true)
        // Assistant is unchanged
        #expect(result[1].content == "ok")
    }

    @Test("a model that cannot see is told so, rather than just that an image is missing")
    func nonVisionPlaceholderExplainsWhy() {
        let blind = MessagePipeline.applyImageStripping(
            [userWithImage()], supportsVision: false
        )
        // The model needs to be able to say it cannot look, not silently ignore the image.
        #expect(blind[0].content?.contains("cannot view images") == true)

        // An image aged out of the live window is a different situation: the model can
        // see, this one is just old.
        let aged = MessagePipeline.applyImageStripping(
            [userWithImage("old"), userWithImage("a"), userWithImage("b"), userWithImage("c")],
            supportsVision: true
        )
        #expect(aged[0].content?.contains("[image omitted]") == true)
        #expect(aged[0].content?.contains("cannot view images") == false)
    }

    // MARK: - Vision model keeps last N turns

    @Test func visionKeepsLastNImageTurns() {
        // 3 image turns; maxLiveImageTurns = 2, so only last 2 keep their attachments
        let messages = [
            userWithImage("first"),
            assistant(),
            userWithImage("second"),
            assistant(),
            userWithImage("third"),
        ]
        let result = MessagePipeline.applyImageStripping(messages, supportsVision: true)

        // First image turn (index 0) should be stripped
        #expect(result[0].attachments == nil || result[0].attachments!.isEmpty)
        #expect(result[0].content?.contains("[image omitted]") == true)

        // Second (index 2) and third (index 4) are within last N — kept
        #expect(result[2].attachments?.isEmpty == false)
        #expect(result[4].attachments?.isEmpty == false)

        // Assistants unchanged
        #expect(result[1].attachments == nil)
        #expect(result[3].attachments == nil)
    }

    @Test func visionWithFewerThanNImageTurnsKeptAll() {
        let messages = [userWithImage(), assistant()]
        let result = MessagePipeline.applyImageStripping(messages, supportsVision: true)
        // Only 1 image turn — within limit
        #expect(result[0].attachments?.isEmpty == false)
    }

    @Test func visionExactlyNImageTurnsKeptAll() {
        let n = MessagePipeline.maxLiveImageTurns
        let imageMessages: [ChatMessage] = (0 ..< n).map { _ in userWithImage() }
        let result = MessagePipeline.applyImageStripping(imageMessages, supportsVision: true)
        // All N image turns kept
        #expect(result.allSatisfy { $0.attachments?.isEmpty == false })
    }

    // MARK: - Text messages unaffected

    @Test func textOnlyMessagesUntouchedByNonVision() {
        let messages = [user("plain text"), assistant("reply"), user("more text")]
        let result = MessagePipeline.applyImageStripping(messages, supportsVision: false)
        #expect(result[0].content == "plain text")
        #expect(result[0].attachments == nil)
        #expect(result[2].content == "more text")
    }

    // MARK: - Placeholder content

    @Test func placeholderAppendedAfterExistingText() {
        let msg = ChatMessage(
            role: "user",
            content: "Look at this:",
            attachments: [imageAttachment()]
        )
        let result = MessagePipeline.applyImageStripping([msg], supportsVision: false)
        let placeholder = MessagePipeline.visionUnsupportedPlaceholder
        #expect(result[0].content == "Look at this:\n\n\(placeholder)")
    }

    @Test func placeholderUsedAloneWhenContentNil() {
        var msg = ChatMessage(role: "user", content: nil)
        msg.attachments = [imageAttachment()]
        let result = MessagePipeline.applyImageStripping([msg], supportsVision: false)
        #expect(result[0].content == MessagePipeline.visionUnsupportedPlaceholder)
    }
}
