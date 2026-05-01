@testable import Eigin
import Foundation
import Testing

@Suite("OnboardingOrchestrator")
struct OnboardingOrchestratorTests {
    let providerID = UUID()
    let baseURL = "https://api.example.com"
    let model = "test-model"

    // MARK: - Test Stages

    /// Stage that extracts a value into `userName`. Completes when non-empty.
    private func nameExtractingStage(id: String = "name") -> OnboardingStage {
        OnboardingStage(
            id: id,
            extractor: OnboardingExtractor(
                tag: id,
                description: "a \(id) value",
                examples: [
                    FewShotExample(
                        userMessage: "Here is my \(id)",
                        assistantResponse: "<\(id) reason=\"test\">\(id)_value</\(id)>"
                    ),
                ]
            ),
            systemHint: { _, _ in "Ask for \(id)." },
            store: { value, _, data, _ in
                guard !value.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                data.userName = value
            },
            isComplete: { $0.userName != nil }
        )
    }

    /// Stage that always shows predefined options.
    private func alwaysOptionStage(
        id: String = "pick",
        options: [String] = ["A", "B"]
    ) -> OnboardingStage {
        OnboardingStage(
            id: id,
            options: { _ in options },
            store: { value, _, data, _ in
                guard !value.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                data.userContext = value
            },
            isComplete: { $0.userContext != nil }
        )
    }

    /// Stage that shows options only on retry, with extraction for freeform input.
    private func retryOptionStage(
        id: String = "style",
        options: [String] = ["Concise", "Sparring"]
    ) -> OnboardingStage {
        OnboardingStage(
            id: id,
            options: { isRetry in isRetry ? options : nil },
            extractor: OnboardingExtractor(
                tag: id,
                description: "a \(id) value",
                examples: [
                    FewShotExample(
                        userMessage: "I like it \(id)",
                        assistantResponse: "<\(id) reason=\"test\">\(id)_value</\(id)>"
                    ),
                ]
            ),
            systemHint: { _, _ in "Ask for \(id)." },
            store: { value, _, data, _ in
                guard !value.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                data.stylePreference = value
            },
            isComplete: { $0.stylePreference != nil }
        )
    }

    /// Stage that returns a scripted opener (used as the target of an advance).
    private func scriptedReplyStage(
        id: String = "scripted",
        response: String = "Done!"
    ) -> OnboardingStage {
        OnboardingStage(
            id: id,
            scriptedOpener: { _ in response },
            store: { value, _, data, _ in
                guard !value.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                data.priority = .power
            },
            isComplete: { $0.priority != nil }
        )
    }

    /// Stage with a recovery opener used after force-advance.
    private func recoveryStage(
        id: String = "recovery",
        recovery: String = "Let's move on!"
    ) -> OnboardingStage {
        OnboardingStage(
            id: id,
            recoveryOpener: { _ in recovery },
            store: { value, _, data, _ in
                guard !value.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                data.userContext = value
            },
            isComplete: { $0.userContext != nil }
        )
    }

    // MARK: - Fake helpers

    private func makeFakeExtraction(tag: String, value: String) -> FakeChatService {
        let fake = FakeChatService()
        fake.enqueueTokens(["<\(tag) reason=\"test\">\(value)</\(tag)>"])
        return fake
    }

    private func makeFailingFake(extraCount: Int = 3) -> FakeChatService {
        let fake = FakeChatService()
        for _ in 0 ... extraCount {
            fake.enqueueTokens(["NONE"])
        }
        return fake
    }

    // MARK: - Greeting & Initial State

    @Test func greetingIsSet() {
        let orchestrator = OnboardingOrchestrator(
            greeting: "Hello!",
            stages: [nameExtractingStage()]
        )
        #expect(orchestrator.greeting == "Hello!")
    }

    @Test func initialStageHasNoOptionsWhenStageProvidesNone() {
        let orchestrator = OnboardingOrchestrator(
            greeting: "Hi",
            stages: [nameExtractingStage()]
        )
        #expect(orchestrator.options == nil)
    }

    @Test func initialStageShowsOptionsWhenStageProvidesThem() {
        let orchestrator = OnboardingOrchestrator(
            greeting: "Hi",
            stages: [alwaysOptionStage()]
        )
        #expect(orchestrator.options == ["A", "B"])
    }

    // MARK: - Send (freeform input)

    @Test func sendWithSuccessfulExtractionStoresValueAndAdvances() async throws {
        let orchestrator = OnboardingOrchestrator(
            greeting: "Hi",
            stages: [nameExtractingStage(), alwaysOptionStage()]
        )
        let fake = makeFakeExtraction(tag: "name", value: "Alice")

        _ = try await orchestrator.send(
            "I'm Alice",
            chatService: fake,
            baseURL: baseURL,
            providerID: providerID,
            model: model,
            conversationHistory: []
        )

        #expect(orchestrator.data.userName == "Alice")
        #expect(orchestrator.currentStageID == "pick")
    }

    @Test func sendReturnsDirectiveWhenAdvancingToHintStage() async throws {
        let orchestrator = OnboardingOrchestrator(
            greeting: "Hi",
            stages: [nameExtractingStage(), alwaysOptionStage()]
        )
        let fake = makeFakeExtraction(tag: "name", value: "Alice")

        let output = try await orchestrator.send(
            "Alice",
            chatService: fake,
            baseURL: baseURL,
            providerID: providerID,
            model: model,
            conversationHistory: []
        )

        if case .directive = output {
            // Expected
        } else {
            Issue.record("Expected .directive, got \(output)")
        }
    }

    @Test func sendReturnsScriptedWhenAdvancingToScriptedStage() async throws {
        let orchestrator = OnboardingOrchestrator(
            greeting: "Hi",
            stages: [nameExtractingStage(), scriptedReplyStage(response: "Nice!")]
        )
        let fake = makeFakeExtraction(tag: "name", value: "Alice")

        let output = try await orchestrator.send(
            "Alice",
            chatService: fake,
            baseURL: baseURL,
            providerID: providerID,
            model: model,
            conversationHistory: []
        )

        if case .scripted(let text) = output {
            #expect(text == "Nice!")
        } else {
            Issue.record("Expected .scripted, got \(output)")
        }
    }

    @Test func sendWithFailedExtractionDoesNotAdvance() async throws {
        let orchestrator = OnboardingOrchestrator(
            greeting: "Hi",
            stages: [nameExtractingStage()]
        )
        let fake = makeFailingFake()

        _ = try await orchestrator.send(
            "Hmm",
            chatService: fake,
            baseURL: baseURL,
            providerID: providerID,
            model: model,
            conversationHistory: []
        )

        #expect(orchestrator.data.userName == nil)
        #expect(orchestrator.currentStageID == "name")
    }

    // MARK: - Retry & Force-advance

    @Test func forceAdvancesAfterMaxRetries() async throws {
        let orchestrator = OnboardingOrchestrator(
            greeting: "Hi",
            stages: [nameExtractingStage()]
        )
        let fake = makeFailingFake()

        // maxRetries = 2, so 3 sends needed: attempts 0, 1 don't give up;
        // on the 3rd send, currentRetryCount (2) >= maxRetries (2), so giveUp triggers.
        _ = try await orchestrator.send(
            "Hello",
            chatService: fake,
            baseURL: baseURL,
            providerID: providerID,
            model: model,
            conversationHistory: []
        )
        #expect(orchestrator.currentStageID == "name")

        _ = try await orchestrator.send(
            "Hi",
            chatService: fake,
            baseURL: baseURL,
            providerID: providerID,
            model: model,
            conversationHistory: []
        )
        #expect(orchestrator.currentStageID == "name")

        _ = try await orchestrator.send(
            "Hey",
            chatService: fake,
            baseURL: baseURL,
            providerID: providerID,
            model: model,
            conversationHistory: []
        )

        #expect(orchestrator.data.userName == nil)
        #expect(orchestrator.isFinished)
    }

    @Test func recoveryOpenerUsedAfterForceAdvance() async throws {
        let orchestrator = OnboardingOrchestrator(
            greeting: "Hi",
            stages: [
                nameExtractingStage(),
                recoveryStage(recovery: "Moving on — what's next?"),
            ]
        )
        let fake = makeFailingFake()

        // 3 failed sends to force-advance name stage
        _ = try await orchestrator.send(
            "a",
            chatService: fake,
            baseURL: baseURL,
            providerID: providerID,
            model: model,
            conversationHistory: []
        )
        _ = try await orchestrator.send(
            "b",
            chatService: fake,
            baseURL: baseURL,
            providerID: providerID,
            model: model,
            conversationHistory: []
        )
        let output = try await orchestrator.send(
            "c",
            chatService: fake,
            baseURL: baseURL,
            providerID: providerID,
            model: model,
            conversationHistory: []
        )

        #expect(orchestrator.data.userName == nil)
        if case .scripted(let text) = output {
            #expect(text == "Moving on — what's next?")
        } else {
            Issue.record("Expected .scripted recovery, got \(output)")
        }
    }

    @Test func recoveryOpenerNotUsedOnNormalAdvance() async throws {
        let orchestrator = OnboardingOrchestrator(
            greeting: "Hi",
            stages: [
                nameExtractingStage(),
                recoveryStage(recovery: "Moving on — what's next?"),
            ]
        )
        let fake = makeFakeExtraction(tag: "name", value: "Alice")

        let output = try await orchestrator.send(
            "Alice",
            chatService: fake,
            baseURL: baseURL,
            providerID: providerID,
            model: model,
            conversationHistory: []
        )

        #expect(orchestrator.data.userName == "Alice")
        if case .directive = output {
            // Expected — normal advance uses directive, not recovery
        } else {
            Issue.record("Expected .directive, got \(output)")
        }
    }

    @Test func optionalStageStoresNothingWhenForceAdvanced() async throws {
        let orchestrator = OnboardingOrchestrator(
            greeting: "Hi",
            stages: [nameExtractingStage()]
        )
        let fake = makeFailingFake()

        _ = try await orchestrator.send(
            "a",
            chatService: fake,
            baseURL: baseURL,
            providerID: providerID,
            model: model,
            conversationHistory: []
        )
        _ = try await orchestrator.send(
            "b",
            chatService: fake,
            baseURL: baseURL,
            providerID: providerID,
            model: model,
            conversationHistory: []
        )
        _ = try await orchestrator.send(
            "c",
            chatService: fake,
            baseURL: baseURL,
            providerID: providerID,
            model: model,
            conversationHistory: []
        )

        #expect(orchestrator.data.userName == nil)
        #expect(orchestrator.isFinished)
    }

    // MARK: - Select (option pick)

    @Test func selectStoresValueWithoutExtraction() async throws {
        let orchestrator = OnboardingOrchestrator(
            greeting: "Hi",
            stages: [alwaysOptionStage()]
        )
        let fake = FakeChatService()

        _ = try await orchestrator.select(
            "B",
            chatService: fake,
            baseURL: baseURL,
            providerID: providerID,
            model: model,
            conversationHistory: []
        )

        #expect(orchestrator.data.userContext == "B")
        #expect(orchestrator.isFinished)
    }

    // MARK: - Retry-only options

    @Test func retryOnlyOptionsNotShownOnFirstAttempt() {
        let orchestrator = OnboardingOrchestrator(
            greeting: "Hi",
            stages: [retryOptionStage()]
        )
        #expect(orchestrator.options == nil)
    }

    @Test func retryOnlyOptionsShownAfterFailedSend() async throws {
        let orchestrator = OnboardingOrchestrator(
            greeting: "Hi",
            stages: [retryOptionStage()]
        )
        let fake = makeFailingFake()

        _ = try await orchestrator.send(
            "Hmm",
            chatService: fake,
            baseURL: baseURL,
            providerID: providerID,
            model: model,
            conversationHistory: []
        )

        #expect(orchestrator.options != nil)
        #expect(orchestrator.options?.contains("Concise") == true)
        #expect(orchestrator.options?.contains("Sparring") == true)
    }

    // MARK: - Summary stage

    /// Stage that always advances, extracting corrections.
    private func summaryStage() -> OnboardingStage {
        OnboardingStage(
            id: "summary",
            extractor: OnboardingExtractor(
                tag: "correction",
                description: "any corrections",
                examples: [
                    FewShotExample(
                        userMessage: "Looks good!",
                        assistantResponse: "NONE"
                    ),
                    FewShotExample(
                        userMessage: "Actually I prefer detailed",
                        assistantResponse: "<correction reason=\"test\">I prefer detailed</correction>"
                    ),
                ]
            ),
            systemHint: { data, _ in
                "Summarize: name=\(data.userName ?? "nil"). Ask if correct."
            },
            store: { value, _, data, _ in
                let trimmed = value.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty, trimmed.lowercased() != "none" {
                    data.summaryCorrection = trimmed
                }
            },
            isComplete: { _ in true }
        )
    }

    @Test func summaryStageAlwaysAdvances() async throws {
        let orchestrator = OnboardingOrchestrator(
            greeting: "Hi",
            stages: [nameExtractingStage(), summaryStage()]
        )
        let fakeName = makeFakeExtraction(tag: "name", value: "Alice")
        let fakeSummary = FakeChatService()
        fakeSummary.enqueueTokens(["NONE"])

        _ = try await orchestrator.send(
            "I'm Alice",
            chatService: fakeName,
            baseURL: baseURL,
            providerID: providerID,
            model: model,
            conversationHistory: []
        )

        let output = try await orchestrator.send(
            "Looks good",
            chatService: fakeSummary,
            baseURL: baseURL,
            providerID: providerID,
            model: model,
            conversationHistory: []
        )

        #expect(orchestrator.isFinished)
        #expect(orchestrator.data.summaryCorrection == nil)
        if case .finished = output {
            // Expected
        } else {
            Issue.record("Expected .finished, got \(output)")
        }
    }

    @Test func summaryStageStoresCorrection() async throws {
        let orchestrator = OnboardingOrchestrator(
            greeting: "Hi",
            stages: [nameExtractingStage(), summaryStage()]
        )
        let fakeName = makeFakeExtraction(tag: "name", value: "Alice")
        let fakeSummary = FakeChatService()
        fakeSummary.enqueueTokens(["<correction reason=\"test\">My name is Bob</correction>"])

        _ = try await orchestrator.send(
            "I'm Alice",
            chatService: fakeName,
            baseURL: baseURL,
            providerID: providerID,
            model: model,
            conversationHistory: []
        )

        _ = try await orchestrator.send(
            "Actually my name is Bob",
            chatService: fakeSummary,
            baseURL: baseURL,
            providerID: providerID,
            model: model,
            conversationHistory: []
        )

        #expect(orchestrator.data.summaryCorrection == "My name is Bob")
        #expect(orchestrator.isFinished)
    }

    @Test func summaryStageTreatsNoneAsNoCorrection() async throws {
        let orchestrator = OnboardingOrchestrator(
            greeting: "Hi",
            stages: [summaryStage()]
        )
        let fake = FakeChatService()
        fake.enqueueTokens(["NONE"])

        _ = try await orchestrator.send(
            "Yes",
            chatService: fake,
            baseURL: baseURL,
            providerID: providerID,
            model: model,
            conversationHistory: []
        )

        #expect(orchestrator.data.summaryCorrection == nil)
        #expect(orchestrator.isFinished)
    }

    // MARK: - Completion

    @Test func signalsFinishedWhenAllStagesComplete() async throws {
        let orchestrator = OnboardingOrchestrator(
            greeting: "Hi",
            stages: [nameExtractingStage(), alwaysOptionStage()]
        )
        let fakeName = makeFakeExtraction(tag: "name", value: "hello")
        let fakePick = FakeChatService()

        _ = try await orchestrator.send(
            "Hello",
            chatService: fakeName,
            baseURL: baseURL,
            providerID: providerID,
            model: model,
            conversationHistory: []
        )

        let output = try await orchestrator.select(
            "A",
            chatService: fakePick,
            baseURL: baseURL,
            providerID: providerID,
            model: model,
            conversationHistory: []
        )

        #expect(orchestrator.isFinished)
        #expect(orchestrator.options == nil)
        if case .finished = output {
            // Expected
        } else {
            Issue.record("Expected .finished, got \(output)")
        }
    }

    @Test func isNotFinishedUntilAllStagesComplete() async throws {
        let orchestrator = OnboardingOrchestrator(
            greeting: "Hi",
            stages: [nameExtractingStage(), alwaysOptionStage()]
        )
        let fake = makeFakeExtraction(tag: "name", value: "hello")

        _ = try await orchestrator.send(
            "Hello",
            chatService: fake,
            baseURL: baseURL,
            providerID: providerID,
            model: model,
            conversationHistory: []
        )

        #expect(!orchestrator.isFinished)
        #expect(orchestrator.currentStageID == "pick")
    }
}
