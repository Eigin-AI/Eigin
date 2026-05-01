@testable import Eigin
import Foundation
import Testing

@Suite("CoreTextGenerationCall")
struct CoreTextGenerationCallTests {
    let providerID = UUID()
    let baseURL = "https://api.example.com"
    let model = "test-model"

    @Test func returnsFullTrimmedOutputForIdentity() async throws {
        let fake = FakeChatService()
        fake.enqueueTokens([
            "\n  A sharp thinking partner who cuts through complexity.  \n",
        ])

        let call = CoreTextGenerationCall(chatService: fake)
        let data = OnboardingData(
            userName: "Daniel",
            userContext: "coding",
            stylePreference: "concise",
            priority: .speed,
            agentName: "Apex",
            agentEmoji: "🦅"
        )

        let result = try await call.run(
            type: .identity,
            data: data,
            language: .english,
            baseURL: baseURL,
            providerID: providerID,
            model: model
        )

        #expect(result == "A sharp thinking partner who cuts through complexity.")
    }

    @Test func returnsFullTrimmedOutputForUser() async throws {
        let fake = FakeChatService()
        fake.enqueueTokens([
            "Daniel builds software and hates fluff.",
        ])

        let call = CoreTextGenerationCall(chatService: fake)
        let data = OnboardingData(userName: "Daniel")

        let result = try await call.run(
            type: .user,
            data: data,
            language: .english,
            baseURL: baseURL,
            providerID: providerID,
            model: model
        )

        #expect(result == "Daniel builds software and hates fluff.")
    }

    @Test func returnsNilForEmptyOutput() async throws {
        let fake = FakeChatService()
        fake.enqueueTokens([])

        let call = CoreTextGenerationCall(chatService: fake)

        let result = try await call.run(
            type: .identity,
            data: OnboardingData(),
            language: .english,
            baseURL: baseURL,
            providerID: providerID,
            model: model
        )

        #expect(result == nil)
    }

    @Test func sendsSystemAndUserMessages() async throws {
        let fake = FakeChatService()
        fake.enqueueTokens(["Test"])

        let call = CoreTextGenerationCall(chatService: fake)
        let data = OnboardingData(
            userName: "Daniel",
            userNameReason: "the user explicitly stated their name"
        )

        _ = try await call.run(
            type: .identity,
            data: data,
            language: .english,
            baseURL: baseURL,
            providerID: providerID,
            model: model
        )

        let capturedMessages = fake.capturedMessages
        #expect(capturedMessages.count == 2)
        #expect(capturedMessages[0].role == "system")
        #expect(capturedMessages[1].role == "user")
    }

    @Test func systemPromptIsGeneralAndGrounding() async throws {
        let fake = FakeChatService()
        fake.enqueueTokens(["Test"])

        let call = CoreTextGenerationCall(chatService: fake)

        _ = try await call.run(
            type: .identity,
            data: OnboardingData(),
            language: .english,
            baseURL: baseURL,
            providerID: providerID,
            model: model
        )

        let capturedMessages = fake.capturedMessages
        let systemMessage = capturedMessages.first { $0.role == "system" }
        let content = systemMessage?.content ?? ""

        #expect(content.contains("core texts"))
        #expect(content.contains("personal AI agents"))
        #expect(!content.contains("English"))
        #expect(!content.contains("Their name is"))
        #expect(!content.contains("Here is an example"))
    }

    @Test func userMessageContainsAntiCopyInstruction() async throws {
        let fake = FakeChatService()
        fake.enqueueTokens(["Test"])

        let call = CoreTextGenerationCall(chatService: fake)

        _ = try await call.run(
            type: .identity,
            data: OnboardingData(),
            language: .english,
            baseURL: baseURL,
            providerID: providerID,
            model: model
        )

        let capturedMessages = fake.capturedMessages
        let userMessage = capturedMessages.last { $0.role == "user" }
        let content = userMessage?.content ?? ""

        #expect(content.contains("completely different user"))
        #expect(content.contains("do not copy"))
        #expect(content.contains("Use your own words"))
    }

    @Test func userMessageContainsDataPointsWithReasons() async throws {
        let fake = FakeChatService()
        fake.enqueueTokens(["Test"])

        let call = CoreTextGenerationCall(chatService: fake)
        let data = OnboardingData(
            userName: "Daniel",
            userNameReason: "the user explicitly stated their name",
            userAbout: "product designer and parent",
            userAboutReason: "the user described their work and family",
            userContext: "coding",
            userContextReason: "the user described their use case",
            stylePreference: "concise",
            stylePreferenceReason: "the user chose concise from options",
            priority: .speed,
            priorityReason: "the user explicitly chose speed",
            agentName: "Apex",
            agentEmoji: "🦅",
            agentNameReason: "the user picked Apex from suggestions",
            summaryCorrection: "I prefer detailed responses",
            summaryCorrectionReason: "the user corrected their earlier choice"
        )

        _ = try await call.run(
            type: .identity,
            data: data,
            language: .english,
            baseURL: baseURL,
            providerID: providerID,
            model: model
        )

        let capturedMessages = fake.capturedMessages
        let userMessage = capturedMessages.last { $0.role == "user" }
        let content = userMessage?.content ?? ""

        #expect(content.contains("Daniel"))
        #expect(content.contains("product designer and parent"))
        #expect(content.contains("coding"))
        #expect(content.contains("concise"))
        #expect(content.contains("speed"))
        #expect(content.contains("Apex"))
        #expect(content.contains("🦅"))
        #expect(content.contains("I prefer detailed responses"))
        #expect(content.contains("the user explicitly stated their name"))
        #expect(content.contains("the user described their work and family"))
        #expect(content.contains("the user described their use case"))
        #expect(content.contains("the user chose concise from options"))
        #expect(content.contains("the user explicitly chose speed"))
        #expect(content.contains("the user picked Apex from suggestions"))
        #expect(content.contains("the user corrected their earlier choice"))
    }

    @Test func userMessageOmitsNilFields() async throws {
        let fake = FakeChatService()
        fake.enqueueTokens(["Test"])

        let call = CoreTextGenerationCall(chatService: fake)
        let data = OnboardingData(agentName: "Agent", agentEmoji: "🤖")

        _ = try await call.run(
            type: .user,
            data: data,
            language: .english,
            baseURL: baseURL,
            providerID: providerID,
            model: model
        )

        let capturedMessages = fake.capturedMessages
        let userMessage = capturedMessages.last { $0.role == "user" }
        let content = userMessage?.content ?? ""

        #expect(!content.contains("Their name is"))
        #expect(!content.contains("They are"))
        #expect(!content.contains("They use AI for"))
        #expect(!content.contains("They prefer"))
        #expect(!content.contains("Their top priority is"))
        #expect(!content.contains("correction"))
    }

    @Test func usesDanishInUserPrompt() async throws {
        let fake = FakeChatService()
        fake.enqueueTokens(["Test"])

        let call = CoreTextGenerationCall(chatService: fake)

        _ = try await call.run(
            type: .identity,
            data: OnboardingData(),
            language: .danish,
            baseURL: baseURL,
            providerID: providerID,
            model: model
        )

        let capturedMessages = fake.capturedMessages
        let userMessage = capturedMessages.last { $0.role == "user" }
        let content = userMessage?.content ?? ""

        #expect(content.contains("Dansk"))
    }

    @Test func usesDefaultReasonWhenReasonIsNil() async throws {
        let fake = FakeChatService()
        fake.enqueueTokens(["Test"])

        let call = CoreTextGenerationCall(chatService: fake)
        let data = OnboardingData(
            userName: "Daniel",
            userContext: "coding"
        )

        _ = try await call.run(
            type: .identity,
            data: data,
            language: .english,
            baseURL: baseURL,
            providerID: providerID,
            model: model
        )

        let capturedMessages = fake.capturedMessages
        let userMessage = capturedMessages.last { $0.role == "user" }
        let content = userMessage?.content ?? ""

        #expect(content.contains("the user told you"))
    }
}
