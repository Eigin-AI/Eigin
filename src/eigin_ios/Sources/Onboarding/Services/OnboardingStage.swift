import Foundation

/// Defines an extraction task for a freeform onboarding stage.
struct OnboardingExtractor {
    let tag: String
    let description: String
    let examples: [FewShotExample]
}

/// A single stage in a guided onboarding conversation.
///
/// Each stage has a specific goal — collect a piece of information from the user.
/// Input arrives either via
/// ``OnboardingOrchestrator/send(_:chatService:baseURL:providerID:model:conversationHistory:)``
/// (freeform text) or
/// ``OnboardingOrchestrator/select(_:chatService:baseURL:providerID:model:conversationHistory:)``
/// (a specific option from a predefined list).
struct OnboardingStage {
    let id: String

    /// Optional predefined options to present to the user alongside free text input.
    /// When the user picks one, the orchestrator calls `select` (no model inference needed).
    /// When the user types instead, the orchestrator calls `send`.
    /// The closure receives `isRetry` so you can choose to only show options if the user gets
    /// stuck.
    let options: @Sendable (_ isRetry: Bool) -> [String]?

    /// Optional extractor to run on freeform input before storing.
    /// If provided, the orchestrator uses `ExtractionCall` to parse the value
    /// out of the user's raw message before calling `store`.
    let extractor: OnboardingExtractor?

    /// An optional ephemeral hint appended to the user message to drive the model's response.
    /// Uses `<system_hint>` format for the model to follow as an imperative instruction.
    let systemHint: @Sendable (_ data: OnboardingData, _ retryCount: Int) -> String?

    /// A scripted opener returned instead of calling the model.
    ///
    /// Use for cases where a brief canned message is better than a model call —
    /// e.g. a summary stage that always shows the same transition.
    let scriptedOpener: (@Sendable (_ data: OnboardingData) -> String)?

    /// Fallback opener used when arriving at this stage from a force-advance.
    ///
    /// Should naturally transition into this stage's topic, e.g.
    /// "Moving on — tell me a bit about yourself."
    let recoveryOpener: (@Sendable (_ data: OnboardingData) -> String)?

    /// Stores the incoming value (from `send` or `select`) into the data.
    /// - Parameters:
    ///   - value: The extracted value, or raw input if extraction failed.
    ///   - reason: The model's stated reason for the extraction, if available.
    ///   - data: The data to update.
    ///   - gaveUp: `true` if the orchestrator exhausted retries and is force-advancing.
    ///     Stages can use this to apply fallback defaults.
    let store: @Sendable (
        _ value: String,
        _ reason: String?,
        _ data: inout OnboardingData,
        _ gaveUp: Bool
    ) -> Void

    /// Returns `true` when this stage has everything it needs and the orchestrator should advance.
    let isComplete: @Sendable (_ data: OnboardingData) -> Bool

    init(
        id: String,
        options: (@Sendable (_ isRetry: Bool) -> [String]?)? = nil,
        extractor: OnboardingExtractor? = nil,
        systemHint: @Sendable @escaping (_ data: OnboardingData, _ retryCount: Int)
            -> String? = { _, _ in nil },
        scriptedOpener: (@Sendable (_ data: OnboardingData) -> String)? = nil,
        recoveryOpener: (@Sendable (_ data: OnboardingData) -> String)? = nil,
        store: @Sendable @escaping (
            _ value: String,
            _ reason: String?,
            _ data: inout OnboardingData,
            _ gaveUp: Bool
        )
            -> Void,
        isComplete: @Sendable @escaping (_ data: OnboardingData) -> Bool
    ) {
        self.id = id
        self.options = options ?? { _ in nil }
        self.extractor = extractor
        self.systemHint = systemHint
        self.scriptedOpener = scriptedOpener
        self.recoveryOpener = recoveryOpener
        self.store = store
        self.isComplete = isComplete
    }
}
