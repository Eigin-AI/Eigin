@testable import Eigin
import Foundation
import Testing

@Suite("ChatTags")
struct ChatTagsTests {
    @Test func stripAllRemovesSystemHintBlock() {
        let input = """
        Hello

        <system_hint>
        ## Interaction mode

        You're in text chat.
        </system_hint>
        """
        let result = ChatTags.stripAll(from: input)
        #expect(result == "Hello")
    }

    @Test func stripAllRemovesSelfClosingSystemHint() {
        let input = "<system_hint />\n\nHow are you?"
        let result = ChatTags.stripAll(from: input)
        #expect(result == "How are you?")
    }

    @Test func stripAllReturnsCleanContentUnchanged() {
        let input = "Just a normal message"
        let result = ChatTags.stripAll(from: input)
        #expect(result == "Just a normal message")
    }

    @Test func stripAllHandlesEmptyString() {
        #expect(ChatTags.stripAll(from: "").isEmpty)
    }

    @Test func stripAllHandlesTagOnly() {
        let input = "<system_hint>\n## Hint\n\nSome hint.\n</system_hint>"
        let result = ChatTags.stripAll(from: input)
        #expect(result.isEmpty)
    }
}
