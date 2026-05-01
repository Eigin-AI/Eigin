@testable import Eigin
import Foundation
import Testing

@Suite("SessionInputs")
struct SessionInputsTests {
    @Test @MainActor func systemMessageBecomesInstructions() {
        let messages = [
            ChatMessage(role: "system", content: "You are helpful."),
            ChatMessage(role: "user", content: "Hello"),
        ]
        let inputs = buildSessionInputs(from: messages)
        #expect(inputs.instructions == "You are helpful.")
        #expect(inputs.prompt == "Hello")
    }

    @Test @MainActor func lastUserMessageBecomesPrompt() {
        let messages = [
            ChatMessage(role: "user", content: "First"),
            ChatMessage(role: "assistant", content: "Response"),
            ChatMessage(role: "user", content: "Second"),
        ]
        let inputs = buildSessionInputs(from: messages)
        #expect(inputs.prompt == "Second")
    }

    @Test @MainActor func chatKeyStableAcrossTurns() {
        let turn1 = [
            ChatMessage(role: "system", content: "You are helpful."),
            ChatMessage(role: "user", content: "Hello"),
        ]
        let turn2 = [
            ChatMessage(role: "system", content: "You are helpful."),
            ChatMessage(role: "user", content: "Hello"),
            ChatMessage(role: "assistant", content: "Hi there!"),
            ChatMessage(role: "user", content: "Nice"),
        ]
        let key1 = buildSessionInputs(from: turn1).chatKey
        let key2 = buildSessionInputs(from: turn2).chatKey
        #expect(key1 == key2, "Same first user message = same chat")
    }

    @Test @MainActor func chatKeyStableWithSystemHint() {
        let withoutHint = [
            ChatMessage(role: "system", content: "You are helpful."),
            ChatMessage(role: "user", content: "Hello"),
        ]
        let withHint = [
            ChatMessage(role: "system", content: "You are helpful."),
            ChatMessage(
                role: "user",
                content: "Hello\n\n<system_hint>Some dynamic info</system_hint>"
            ),
        ]
        let key1 = buildSessionInputs(from: withoutHint).chatKey
        let key2 = buildSessionInputs(from: withHint).chatKey
        #expect(key1 == key2, "System hint should not affect chat key stability")
    }

    @Test @MainActor func emptyMessagesDefaultToHello() {
        let inputs = buildSessionInputs(from: [])
        #expect(inputs.instructions == nil)
        #expect(inputs.prompt == "Hello")
    }

    @Test @MainActor func multipleSystemMessagesJoined() {
        let messages = [
            ChatMessage(role: "system", content: "You are helpful."),
            ChatMessage(role: "system", content: "Be concise."),
            ChatMessage(role: "user", content: "Hi"),
        ]
        let inputs = buildSessionInputs(from: messages)
        #expect(inputs.instructions == "You are helpful.\n\nBe concise.")
    }
}
