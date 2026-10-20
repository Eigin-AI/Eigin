@testable import Eigin
import Foundation
import Testing

@Suite("VocabularyHintSource")
@MainActor
struct VocabularyHintSourceTests {
    private func input(
        mode: InteractionMode,
        transcript: String? = nil,
        vocabulary: [VocabularyEntry] = []
    ) -> SystemHintInput {
        var input = SystemHintInput(
            agentID: UUID(),
            bootstrapComplete: true,
            needsCompaction: false,
            hasSpaces: false,
            messages: transcript.map { [ChatMessage(role: "user", content: $0)] } ?? [],
            space: nil,
            spaceID: nil,
            language: nil,
            mode: mode,
            activeIntents: [],
            activeSkills: [],
            availableSkills: [],
            activeFlow: nil,
            provider: ProviderSnapshot(name: "Test", baseURL: "https://test.com"),
            modelID: "test-model",
            isSmallContext: false
        )
        input.vocabulary = vocabulary
        return input
    }

    private func render(_ input: SystemHintInput) async -> String? {
        await VocabularyHintSource().render(input)
    }

    @Test func silentForTextMode() async {
        let result = await render(input(
            mode: .text,
            transcript: "mention tackle",
            vocabulary: [VocabularyEntry(word: "Therkel", aliases: ["tackle"])]
        ))
        #expect(result == nil)
    }

    @Test func silentWithoutVocabulary() async {
        let result = await render(input(mode: .dictation, transcript: "tackle"))
        #expect(result == nil)
    }

    @Test func silentWithoutUserMessage() async {
        let result = await render(input(mode: .dictation, vocabulary: [
            VocabularyEntry(word: "Therkel", aliases: ["tackle"]),
        ]))
        #expect(result == nil)
    }

    @Test func silentWhenNoMistranscription() async {
        let result = await render(input(
            mode: .liveCall,
            transcript: "hello Therkel",
            vocabulary: [VocabularyEntry(word: "Therkel", aliases: ["tackle"])]
        ))
        #expect(result == nil)
    }

    @Test func rendersAliasMatchWithGuidance() async throws {
        let result = await render(input(
            mode: .dictation,
            transcript: "ask tackle about lunch",
            vocabulary: [VocabularyEntry(word: "Therkel", aliases: ["tackle"])]
        ))
        let body = try #require(result)
        #expect(body.contains("- tackle → Therkel"))
        #expect(!body.contains("Therkel?"))
        #expect(body.contains("mistranscriptions"))
    }

    @Test func rendersDistanceMatchAsPossibility() async {
        let result = await render(input(
            mode: .headless,
            transcript: "what's new on eigen",
            vocabulary: [VocabularyEntry(word: "Eigin")]
        ))
        #expect(result?.contains("- eigen → Eigin?") == true)
    }
}
