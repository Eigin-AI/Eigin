import Foundation

/// Output of the Gatekeeper's per-turn preprocessing pass.
///
/// Carries the ephemeral `<system_hint>` block plus any tool-call *intents* to
/// run immediately before the turn (today: skill activations from trigger
/// matching, but the channel is generic). Intents are data, not execution: the
/// agent loop runs them as a synthetic pre-round (see ``AgenticChatLoop/run``).
struct TurnPreprocessing {
    let hint: String?
    let toolCallIntents: [ToolCall]
}

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
/// A `beforeTurn` hook produces the hint block plus any tool-call intents to
/// run immediately (today: skill activations from trigger matching); an
/// `afterTurn` hook is reserved as a seam for future pre/post-processing (PII
/// scrubbing, local model delegation, etc.) but is a no-op today.
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
            SeasonalInfoSource(),
            SpaceSource(),
            LanguageSource(),
            InteractionModeSource(),
            ActiveSkillsSource(),
            ActiveFlowSource(),
            AvailableSkillsSource(),
            ActiveIntentsSource(),
            ChatHintSource(proactivity: proactivity),
            RelevantKnowledgeSource(knowledgeService: knowledgeService),
        ]
        smallSources = [
            GeneralInfoSource(),
            LanguageSource(),
            SpaceSource(),
            InteractionModeSource(),
            ActiveIntentsSource(),
            RelevantKnowledgeSource(knowledgeService: knowledgeService),
        ]
    }

    // MARK: - Pre/post hooks

    /// Preprocesses the user turn: builds the ephemeral `<system_hint>` block
    /// and matches trigger keywords into tool-call intents to run immediately.
    func beforeTurn(_ input: SystemHintInput) async -> TurnPreprocessing {
        let sources = input.isSmallContext ? smallSources : fullSources
        let hint = await SystemHintBuilder.build(sources: sources, input: input)
        return TurnPreprocessing(hint: hint, toolCallIntents: activationIntents(for: input))
    }

    /// Matches the latest user message against activatable skills' triggers and
    /// returns `activate_skill` tool-call intents (capped by ``SkillHydrator``).
    ///
    /// MCP skills are gated implicitly: for small-context models ``input``
    /// carries no MCP skills in `availableSkills`, so only bundled skills match.
    private func activationIntents(for input: SystemHintInput) -> [ToolCall] {
        guard let userText = input.messages.last(where: { $0.role == "user" })?.content,
              !userText.isEmpty else { return [] }

        let activeIDs = Set(input.activeSkills.map(\.id))
        let candidates = SkillCatalog.activatable(
            from: input.availableSkills,
            activeIDs: activeIDs,
            connectedCapabilities: input.connectedCapabilities
        )
        let matchedIDs = SkillHydrator.matches(userText: userText, candidates: candidates)
        return matchedIDs.map { skillID in
            ToolCall(
                id: "call_auto_\(UUID().uuidString.prefix(8))",
                type: "function",
                function: .init(
                    name: "activate_skill",
                    arguments: "{\"skill_id\":\"\(skillID)\"}"
                )
            )
        }
    }

    /// Post-processor seam called after a turn completes.
    ///
    /// No-op today. Reserved for future pre/post-processing hooks such as
    /// PII scrubbing or local model delegation.
    func afterTurn(_ messages: [ChatMessage]) {
        // Intentionally empty.
    }
}
