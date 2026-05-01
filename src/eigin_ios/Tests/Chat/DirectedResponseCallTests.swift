@testable import Eigin
import Foundation
import Testing

@Suite("DirectedResponseCall")
struct DirectedResponseCallTests {
    let providerID = UUID()
    let baseURL = "https://api.example.com"
    let model = "test-model"

    @Test func prependsSystemPromptToHistory() async throws {
        let fake = FakeChatService()
        fake.enqueueTokens(["Hello", " there"])

        let history = [
            ChatMessage(role: "user", content: "Hey"),
            ChatMessage(role: "assistant", content: "Hi!"),
            ChatMessage(role: "user", content: "What's my name?"),
        ]

        let call = DirectedResponseCall(chatService: fake)
        let stream = try await call.stream(
            systemPrompt: "The user's name is Daniel. Tell them their name.",
            conversationHistory: history,
            baseURL: baseURL,
            providerID: providerID,
            model: model
        )

        var response = ""
        for try await token in stream {
            response += token
        }
        #expect(response == "Hello there")

        let messages = fake.capturedMessages
        #expect(messages.count == 4)
        #expect(messages[0].role == "system")
        #expect(messages[0].content == "The user's name is Daniel. Tell them their name.")
        #expect(messages[1].role == "user")
        #expect(messages[2].role == "assistant")
        #expect(messages[3].role == "user")
    }

    @Test func worksWithEmptyHistory() async throws {
        let fake = FakeChatService()
        fake.enqueueTokens(["Hi, what's your name?"])

        let call = DirectedResponseCall(chatService: fake)
        let stream = try await call.stream(
            systemPrompt: "Ask the user for their name.",
            conversationHistory: [],
            baseURL: baseURL,
            providerID: providerID,
            model: model
        )

        var response = ""
        for try await token in stream {
            response += token
        }
        #expect(response == "Hi, what's your name?")

        let messages = fake.capturedMessages
        #expect(messages.count == 1)
        #expect(messages[0].role == "system")
    }
}
