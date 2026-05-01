@testable import Eigin
import Foundation
import Testing

@Suite("ExtractionCall")
struct ExtractionCallTests {
    let providerID = UUID()
    let baseURL = "https://api.example.com"
    let model = "test-model"

    let examples = [
        FewShotExample(
            userMessage: "Oh hi there, I'm Matt the cat",
            assistantResponse: #"<name reason="User said their name was Matt">Matt</name>"#
        ),
        FewShotExample(
            userMessage: "This is Tracy",
            assistantResponse: #"<name reason="The user is Tracy">Tracy</name>"#
        ),
    ]

    @Test func extractsNameFromValidResponse() async throws {
        let fake = FakeChatService()
        fake.enqueueTokens([#"<name reason="User said people call me Daniel">Daniel</name>"#])

        let call = ExtractionCall(chatService: fake)
        let result = try await call.run(
            tag: "name",
            description: "the user's name",
            examples: examples,
            input: "Hey I think this is cool, people call me Daniel",
            baseURL: baseURL,
            providerID: providerID,
            model: model
        )

        #expect(result == .extracted(value: "Daniel", reason: "User said people call me Daniel"))
    }

    @Test func returnsNoMatchWhenModelSaysNone() async throws {
        let fake = FakeChatService()
        fake.enqueueTokens(["NONE"])

        let call = ExtractionCall(chatService: fake)
        let result = try await call.run(
            tag: "name",
            description: "the user's name",
            examples: examples,
            input: "I just want to look around",
            baseURL: baseURL,
            providerID: providerID,
            model: model
        )

        if case .noMatch = result {
            // Expected
        } else {
            Issue.record("Expected .noMatch, got \(result)")
        }
    }

    @Test func returnsEmptyForBlankModelOutput() async throws {
        let fake = FakeChatService()
        fake.enqueueTokens([])

        let call = ExtractionCall(chatService: fake)
        let result = try await call.run(
            tag: "name",
            description: "the user's name",
            examples: examples,
            input: "...",
            baseURL: baseURL,
            providerID: providerID,
            model: model
        )

        #expect(result == .empty)
    }

    @Test func takesLastOccurrenceWhenModelEchoesExamples() async throws {
        // Model echoes a few-shot example before producing the real answer
        let fake = FakeChatService()
        fake.enqueueTokens([
            #"<name reason="Example echo">Matt</name>"#,
            "\n",
            #"<name reason="User said people call me Daniel">Daniel</name>"#,
        ])

        let call = ExtractionCall(chatService: fake)
        let result = try await call.run(
            tag: "name",
            description: "the user's name",
            examples: examples,
            input: "people call me Daniel",
            baseURL: baseURL,
            providerID: providerID,
            model: model
        )

        #expect(result == .extracted(value: "Daniel", reason: "User said people call me Daniel"))
    }

    @Test func systemPromptContainsTagAndDescription() async throws {
        let fake = FakeChatService()
        fake.enqueueTokens(["NONE"])

        let call = ExtractionCall(chatService: fake)
        _ = try await call.run(
            tag: "preference",
            description: "the user's communication preference",
            examples: [],
            input: "test",
            baseURL: baseURL,
            providerID: providerID,
            model: model
        )

        let capturedMessages = fake.capturedMessages
        let systemMessage = capturedMessages.first { $0.role == "system" }
        let content = systemMessage?.content ?? ""
        #expect(content.contains("preference"))
        #expect(content.contains("the user's communication preference"))
    }

    @Test func contextPrependsAssistantMessageToInput() async throws {
        let fake = FakeChatService()
        fake.enqueueTokens([#"<name reason="User confirmed Dan">Dan</name>"#])

        let call = ExtractionCall(chatService: fake)
        let result = try await call.run(
            tag: "name",
            description: "the user's name",
            examples: examples,
            input: "Yeah that's me",
            context: "What should I call you?",
            baseURL: baseURL,
            providerID: providerID,
            model: model
        )

        let capturedMessages = fake.capturedMessages
        let lastUserMessage = capturedMessages.last { $0.role == "user" }
        let content = lastUserMessage?.content ?? ""
        #expect(content == "[Assistant: \"What should I call you?\"] \"Yeah that's me\"")
        #expect(result == .extracted(value: "Dan", reason: "User confirmed Dan"))
    }

    @Test func nilContextPassesInputThroughUnchanged() async throws {
        let fake = FakeChatService()
        fake.enqueueTokens([#"<name reason="User said Daniel">Daniel</name>"#])

        let call = ExtractionCall(chatService: fake)
        _ = try await call.run(
            tag: "name",
            description: "the user's name",
            examples: examples,
            input: "I'm Daniel",
            context: nil,
            baseURL: baseURL,
            providerID: providerID,
            model: model
        )

        let capturedMessages = fake.capturedMessages
        let lastUserMessage = capturedMessages.last { $0.role == "user" }
        #expect(lastUserMessage?.content == "I'm Daniel")
    }
}
