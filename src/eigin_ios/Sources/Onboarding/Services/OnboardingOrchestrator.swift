import Foundation
import Observation

/// The user's selected priority — maps to concrete app settings.
enum OnboardingPriority: String, CaseIterable {
    case power, speed, freedom, privacy
}

/// Data collected during the guided onboarding conversation.
struct OnboardingData {
    var userName: String?
    var userNameReason: String?
    var userAbout: String?
    var userAboutReason: String?
    var userContext: String?
    var userContextReason: String?
    var stylePreference: String?
    var stylePreferenceReason: String?
    var priority: OnboardingPriority?
    var priorityReason: String?
    var agentName: String?
    var agentEmoji: String?
    var agentNameReason: String?
    /// Any correction the user provided during the summary confirmation stage.
    /// `nil` means they confirmed without changes.
    var summaryCorrection: String?
    var summaryCorrectionReason: String?
}

/// The result of an orchestrator turn.
enum OrchestratorOutput {
    /// A directive with optional hint for the model to follow.
    case directive(systemHint: String?)
    /// A scripted response — display directly without a model call.
    case scripted(String)
    /// All stages are complete.
    case finished
}

/// Drives a staged guided conversation using ``DirectedResponseCall``.
///
/// Each stage has a specific goal. The orchestrator advances through stages as
/// the user provides information, either by selecting a predefined option or by
/// sending freeform text. When all stages are complete it signals `.finished`.
///
/// Usage:
/// ```swift
/// let orchestrator = OnboardingOrchestrator(
///     greeting: "Hi! What's your name?",
///     stages: LocalOnboardingScript.stages
/// )
/// // Display orchestrator.greeting as the first assistant message.
/// // On user input:
/// let output = try await orchestrator.send(text, chatService: ..., ...)
/// ```
@Observable
final class OnboardingOrchestrator: @unchecked Sendable {
    /// Options to present to the user. `nil` means free text only.
    private(set) var options: [String]?
    /// All stages have been completed.
    private(set) var isFinished = false
    /// The data collected so far.
    private(set) var data = OnboardingData()

    /// Scripted opening message to display before any user input.
    let greeting: String

    private let stages: [OnboardingStage]
    private var stageIndex = 0
    /// Number of freeform `send` attempts per stage ID that did not advance.
    private var sendAttempts: [String: Int] = [:]
    /// Maximum freeform send attempts before forcing advance to next stage.
    private let maxRetries = 2
    /// Tracks whether the previous stage was force-advanced, so the next stage
    /// can use its recovery opener instead of the normal model-driven flow.
    private var previousStageGaveUp = false

    init(greeting: String, stages: [OnboardingStage]) {
        self.greeting = greeting
        self.stages = stages
        options = stages.first?.options(false)
    }

    /// The ID of the current stage, or `nil` if finished.
    var currentStageID: String? {
        guard stageIndex < stages.count else { return nil }
        return stages[stageIndex].id
    }

    // MARK: - Input

    /// Process a freeform user message. Stores the raw text and generates a directed response.
    func send(
        _ text: String,
        chatService: ChatService,
        baseURL: String,
        providerID: UUID,
        model: String,
        conversationHistory: [ChatMessage]
    ) async throws -> OrchestratorOutput {
        try await process(
            value: text,
            isSend: true,
            chatService: chatService,
            baseURL: baseURL,
            providerID: providerID,
            model: model,
            conversationHistory: conversationHistory
        )
    }

    /// Process a specific option selection. Stores the value directly and generates a response.
    func select(
        _ value: String,
        chatService: ChatService,
        baseURL: String,
        providerID: UUID,
        model: String,
        conversationHistory: [ChatMessage]
    ) async throws -> OrchestratorOutput {
        try await process(
            value: value,
            isSend: false,
            chatService: chatService,
            baseURL: baseURL,
            providerID: providerID,
            model: model,
            conversationHistory: conversationHistory
        )
    }

    // MARK: - Private

    private func process(
        value: String,
        isSend: Bool,
        chatService: ChatService,
        baseURL: String,
        providerID: UUID,
        model: String,
        conversationHistory: [ChatMessage]
    ) async throws -> OrchestratorOutput {
        guard stageIndex < stages.count else {
            isFinished = true
            return .finished
        }

        let stage = stages[stageIndex]

        AppLogger.debug("Processing stage \(public: stage.id)", category: .onboarding)

        var processedValue = value
        var extractionReason: String?

        // 1. Check if the value matches an option exactly (case-insensitive)
        let currentOptions = stage.options(false) ?? []
        let matchedOption = currentOptions.first { $0.lowercased() == value.lowercased() }

        // 2. If it matches an option, we bypass extraction
        if let matched = matchedOption {
            AppLogger.debug(
                "Input matches option, bypassing extraction",
                category: .onboarding
            )
            processedValue = matched
        }
        // 3. Otherwise, if it's a send and we have an extractor, run it
        else if isSend, let extractor = stage.extractor {
            let lastAssistantMessage = conversationHistory.last(where: { $0.role == "assistant" })?
                .content
            let call = ExtractionCall(chatService: chatService)
            let result = try await call.run(
                tag: extractor.tag,
                description: extractor.description,
                examples: extractor.examples,
                input: value,
                context: lastAssistantMessage,
                baseURL: baseURL,
                providerID: providerID,
                model: model
            )

            switch result {
            case .extracted(let extractedValue, let reason):
                let extractedTrimmed = extractedValue.trimmingCharacters(in: .whitespaces)
                if extractedTrimmed.lowercased() == "none" || extractedTrimmed.isEmpty {
                    AppLogger.debug(
                        "Extraction for \(public: stage.id) returned empty",
                        category: .onboarding
                    )
                    processedValue = ""
                } else {
                    AppLogger.debug(
                        "Extraction for \(public: stage.id) succeeded",
                        category: .onboarding
                    )
                    processedValue = extractedTrimmed
                    extractionReason = reason
                }
            case .noMatch:
                AppLogger.debug(
                    "Extraction for \(public: stage.id) failed to match",
                    category: .onboarding
                )
                processedValue = ""
            case .empty:
                AppLogger.debug(
                    "Extraction for \(public: stage.id) returned empty",
                    category: .onboarding
                )
                processedValue = ""
            }
        }

        let currentRetryCount = sendAttempts[stage.id] ?? 0
        let gaveUp = isSend && currentRetryCount >= maxRetries

        // Store the value and check if this stage is now complete
        if gaveUp {
            // Force-advance: store nothing if extraction failed, then move on
            let valueToStore = processedValue.isEmpty ? "" : processedValue
            stage.store(valueToStore, extractionReason, &data, true)
            stageIndex += 1
            sendAttempts[stage.id] = nil
            previousStageGaveUp = true
        } else {
            stage.store(processedValue, extractionReason, &data, false)
            let advanced = stage.isComplete(data)
            if advanced {
                stageIndex += 1
                sendAttempts[stage.id] = nil
                previousStageGaveUp = false
            } else if isSend {
                sendAttempts[stage.id, default: 0] += 1
            }
        }

        AppLogger.debug(
            "Stage complete — gaveUp: \(public: gaveUp), stageIndex: \(public: stageIndex)/\(public: stages.count)",
            category: .onboarding
        )

        // All stages done
        if stageIndex >= stages.count {
            isFinished = true
            options = nil
            return .finished
        }

        let newStage = stages[stageIndex]

        let retryCount = isSend ? (sendAttempts[newStage.id] ?? 0) : 0

        options = newStage.options(retryCount > 0)

        AppLogger.debug(
            "Advanced to stage \(public: newStage.id)",
            category: .onboarding
        )

        if let scripted = newStage.scriptedOpener {
            return .scripted(scripted(data))
        }

        if previousStageGaveUp, let recovery = newStage.recoveryOpener {
            previousStageGaveUp = false
            return .scripted(recovery(data))
        }

        let systemHintText = newStage.systemHint(data, retryCount)
        return .directive(systemHint: systemHintText)
    }
}
