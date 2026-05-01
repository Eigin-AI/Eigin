import Foundation

/// Pre/post-processor sitting between the agent and the LLM.
///
/// `Gatekeeper` is the entry point for unified per-turn context hydration. It
/// owns an ordered list of ``SystemHintSource``s, calls each once per turn,
/// and composes the result into a single ephemeral `<system_hint>` block that
/// is appended by ``MessagePipeline`` to the latest real user message just
/// before the request goes to the LLM.
///
/// The Gatekeeper itself is stateless — per-section state (e.g. the last
/// emitted interaction mode, whether a chat hint has already fired this
/// session) lives on the sources themselves. One instance is constructed per
/// chat or live-call session and dies with it.
///
/// A `beforeTurn` hook produces the hint block; an `afterTurn` hook is
/// reserved as a seam for future pre/post-processing (PII scrubbing, local
/// model delegation, etc.) but is a no-op today.
@MainActor
final class Gatekeeper {
    // MARK: - Source lists

    /// Ordered list of sources used for full-context models.
    ///
    /// The order here is the order sections appear in the rendered block.
    /// Sources that take up more contextual real estate (space, language,
    /// skills) come before the lighter-weight hint at the end.
    private let fullSources: [any SystemHintSource]

    /// Source list for small-context models (≤16K).
    ///
    /// Minimal hint — just time/model info and truncated intents/skills.
    /// Each source checks ``SystemHintInput/isSmallContext`` and truncates.
    private let smallSources: [any SystemHintSource]

    // MARK: - Init

    init(
        proactivity: ProactivityLevel,
        knowledgeService: any KnowledgeService
    ) {
        fullSources = [
            GeneralInfoSource(),
            SpaceSource(),
            LanguageSource(),
            ActiveSkillsSource(),
            AvailableSkillsSource(),
            ActiveIntentsSource(),
            InteractionModeSource(),
            ChatHintSource(proactivity: proactivity),
            RelevantKnowledgeSource(knowledgeService: knowledgeService),
        ]
        // Note: AvailableSkillsSource is deliberately excluded for small
        // context. The native Gemma tool declaration for `activate_skill`
        // already carries the list of skill IDs in its `enum` parameter,
        // so duplicating it as a markdown list in the hint just adds
        // tokens and over-emphasizes skill names in a way that confused
        // the E2B model's tool call generation.
        smallSources = [
            GeneralInfoSource(),
            LanguageSource(),
        ]
    }

    // MARK: - Pre/post hooks

    /// Builds the ephemeral `<system_hint>` block for this turn, or `nil` if
    /// no source had anything to contribute.
    func beforeTurn(_ input: SystemHintInput) async -> String? {
        let sources = input.isSmallContext ? smallSources : fullSources
        return await SystemHintBuilder.build(sources: sources, input: input)
    }

    /// Post-processor seam called after a turn completes.
    ///
    /// No-op today. Reserved for future pre/post-processing hooks such as
    /// PII scrubbing or local model delegation.
    func afterTurn(_ messages: [ChatMessage]) {
        // Intentionally empty.
    }
}
