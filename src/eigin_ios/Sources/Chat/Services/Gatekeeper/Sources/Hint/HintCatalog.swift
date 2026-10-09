import Foundation

/// A single hint definition: what to say, when it's relevant, and how often.
struct HintType {
    let id: String
    let cooldown: TimeInterval
    /// Consecutive eligible turns the hint may fire before its cooldown
    /// applies. 1 = fire once, then wait out the cooldown. Useful when the
    /// right moment to act on the hint may arrive a few turns later.
    var burst: Int = 1
    let priority: Int
    let condition: @Sendable (HintContext) -> Bool
    let template: @Sendable (HintContext) -> String
}

/// Snapshot of agent/chat state passed to hint conditions and templates.
struct HintContext {
    let messages: [ChatMessage]
    let hasSpaces: Bool
    let needsCompaction: Bool
    let initiative: ProactivityLevel
}

/// The catalog of all available hint types.
///
/// Hint templates return plain markdown text — the content that will appear in
/// the ``Gatekeeper``'s ephemeral `<system_hint>` block under a hint section.
enum HintCatalog {
    static let all: [HintType] = [
        revisitCoreDocs,
        collectKnowledge,
        selfConfigure,
        compactionWarning,
        capabilitySpaces,
        introduceInitiative,
    ]

    // MARK: - Hint Definitions

    /// Periodically encourage the agent to revisit user/identity core docs.
    static let revisitCoreDocs = HintType(
        id: "revisit_core_docs",
        cooldown: 3 * 86400, // 3 days
        burst: 8,
        priority: 5,
        condition: { _ in true },
        template: { _ in Prompt.Hints.Chat.revisitCoreDocs }
    )

    /// Nudge the agent to save concrete details from the conversation as knowledge.
    static let collectKnowledge = HintType(
        id: "collect_knowledge",
        cooldown: 86400, // 1 day
        burst: 4,
        priority: 6,
        condition: { ctx in ctx.messages.count >= 6 },
        template: { _ in Prompt.Hints.Chat.collectKnowledge }
    )

    /// Suggest the agent check in with the user about their setup preferences.
    static let selfConfigure = HintType(
        id: "self_configure",
        cooldown: 7 * 86400, // 7 days
        burst: 8,
        priority: 3,
        condition: { _ in true },
        template: { _ in Prompt.Hints.Chat.selfConfigure }
    )

    /// Warn when the conversation is approaching auto-compaction.
    /// Cooldown is 0, so it's eligible every turn while relevant — a burst
    /// would have no effect here.
    static let compactionWarning = HintType(
        id: "compaction_warning",
        cooldown: 0, // no cooldown — fires whenever relevant
        priority: 10,
        condition: { ctx in ctx.needsCompaction },
        template: { _ in Prompt.Hints.Chat.compactionWarning }
    )

    /// Suggest spaces for users who don't have any yet.
    static let capabilitySpaces = HintType(
        id: "capability_spaces",
        cooldown: 14 * 86400, // 14 days
        burst: 8,
        priority: 1,
        condition: { ctx in !ctx.hasSpaces },
        template: { _ in Prompt.Hints.Chat.capabilitySpaces }
    )

    /// Prompt the agent to offer proactivity to users who haven't decided yet.
    ///
    /// Priority sits above the routine conversation hints (knowledge collection,
    /// core docs) so the offer lands within the first exchanges — once the user
    /// has decided, the condition goes false and the hint never fires again.
    ///
    /// The burst keeps the hint present on every turn for the first stretch of
    /// use: the agent should only act when a concrete reason shows up, and
    /// that reason may arrive a few turns after the hint's first appearance.
    static let introduceInitiative = HintType(
        id: "introduce_initiative",
        cooldown: 86400, // 1 day between bursts
        burst: 8,
        priority: 7,
        condition: { ctx in
            ctx.initiative == .reactive && !ProactivityDecision.isDecided()
        },
        template: { _ in Prompt.Hints.Chat.introduceInitiative }
    )
}
