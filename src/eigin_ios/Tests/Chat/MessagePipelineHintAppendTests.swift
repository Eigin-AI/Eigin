@testable import Eigin
import Foundation
import Testing

@Suite("MessagePipeline hint append & cache stability")
@MainActor
struct MessagePipelineHintAppendTests {
    // MARK: - Helpers

    private func agent(
        name: String = "Test",
        identity: String = "",
        userCore: String = ""
    ) -> Agent {
        let a = Agent(name: name, providerID: UUID(), model: "gpt-4o")
        a.identityCore = identity
        a.userCore = userCore
        return a
    }

    // MARK: - Hint appended to last user message

    @Test func hintAppendedToLastUserMessage() {
        let agent = agent()
        let messages = [
            ChatMessage(role: "user", content: "first"),
            ChatMessage(role: "assistant", content: "reply"),
            ChatMessage(role: "user", content: "second"),
        ]
        let output = MessagePipeline.buildAPIMessages(
            agent: agent,
            conversationMessages: messages,
            systemHint: "<system_hint>\n## Test\n\nbody\n</system_hint>"
        )
        // system + user + assistant + user
        #expect(output.count == 4)
        #expect(output.last?.role == "user")
        #expect(output.last?.content == "second\n\n<system_hint>\n## Test\n\nbody\n</system_hint>")
        // Earlier user message should be untouched.
        #expect(output[1].content == "first")
    }

    @Test func hintWalksBackPastAssistantAndToolResults() {
        let agent = agent()
        let messages = [
            ChatMessage(role: "user", content: "real"),
            ChatMessage(role: "assistant", content: "ok"),
        ]
        let output = MessagePipeline.buildAPIMessages(
            agent: agent,
            conversationMessages: messages,
            systemHint: "HINT"
        )
        // system + user + assistant
        #expect(output.count == 3)
        // Hint should be appended to the user, not the assistant.
        #expect(output[1].role == "user")
        #expect(output[1].content?.contains("real\n\nHINT") == true)
        #expect(output[2].role == "assistant")
        #expect(output[2].content == "ok")
    }

    @Test func nilHintProducesPlainConversation() {
        let agent = agent()
        let messages = [ChatMessage(role: "user", content: "hello")]
        let output = MessagePipeline.buildAPIMessages(
            agent: agent,
            conversationMessages: messages,
            systemHint: nil
        )
        #expect(output.count == 2)
        #expect(output[1].content == "hello")
    }

    @Test func originalMessagesNotMutated() {
        let agent = agent()
        let originalUser = ChatMessage(role: "user", content: "hi")
        let messages = [originalUser]
        _ = MessagePipeline.buildAPIMessages(
            agent: agent,
            conversationMessages: messages,
            systemHint: "HINT"
        )
        // The caller's array reference (value-semantics for Swift struct,
        // but the content field should not have been mutated via any aliasing).
        #expect(messages[0].content == "hi")
        #expect(originalUser.content == "hi")
    }

    // MARK: - Cache stability

    @Test func systemPromptByteStableAcrossTurns() {
        let agent = agent(identity: "I am a helpful agent.", userCore: "User likes Rust.")
        let firstTurn = MessagePipeline.buildAPIMessages(
            agent: agent,
            conversationMessages: [ChatMessage(role: "user", content: "one")],
            systemHint: "<system_hint>\n## A\n\none\n</system_hint>"
        )
        let secondTurn = MessagePipeline.buildAPIMessages(
            agent: agent,
            conversationMessages: [
                ChatMessage(role: "user", content: "one"),
                ChatMessage(role: "assistant", content: "ok"),
                ChatMessage(role: "user", content: "two"),
            ],
            systemHint: "<system_hint>\n## B\n\ntwo\n</system_hint>"
        )
        #expect(firstTurn.first?.role == "system")
        #expect(secondTurn.first?.role == "system")
        #expect(firstTurn.first?.content == secondTurn.first?.content)
    }

    // MARK: - Synthetic compaction messages

    @Test func compactionSummaryEmitsSyntheticUserAssistantPair() {
        let agent = agent()
        let output = MessagePipeline.buildAPIMessages(
            agent: agent,
            conversationMessages: [ChatMessage(role: "user", content: "ongoing")],
            compactionSummary: "Earlier the user asked about Rust.",
            systemHint: "HINT"
        )
        // Expected: system, synthetic user (summary), synthetic assistant ack, real user with hint appended.
        #expect(output.count == 4)
        #expect(output[0].role == "system")
        #expect(output[1].role == "user")
        #expect(output[1].content?.contains("<conversation_summary>") == true)
        #expect(output[1].content?.contains("Earlier the user asked about Rust.") == true)
        #expect(output[2].role == "assistant")
        #expect(output[3].role == "user")
        #expect(output[3].content?.contains("ongoing\n\nHINT") == true)
        // Synthetic user (summary) must NOT carry the hint.
        #expect(output[1].content?.contains("HINT") == false)
    }

    @Test func compactionSummaryAbsentFromSystemPrompt() {
        let agent = agent()
        let output = MessagePipeline.buildAPIMessages(
            agent: agent,
            conversationMessages: [ChatMessage(role: "user", content: "ongoing")],
            compactionSummary: "SECRET_SUMMARY_TOKEN",
            systemHint: nil
        )
        #expect(output[0].content?.contains("SECRET_SUMMARY_TOKEN") == false)
    }

    @Test func noCompactionSummaryNoSynthetic() {
        let agent = agent()
        let output = MessagePipeline.buildAPIMessages(
            agent: agent,
            conversationMessages: [ChatMessage(role: "user", content: "hi")],
            compactionSummary: nil,
            systemHint: nil
        )
        // Just system + user.
        #expect(output.count == 2)
        #expect(output[0].role == "system")
        #expect(output[1].role == "user")
    }
}
