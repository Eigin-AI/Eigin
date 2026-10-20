import Foundation

/// Per-turn inputs passed to every ``SystemHintSource``.
///
/// Sources read only the fields they need. Using primitives + snapshot types
/// (rather than SwiftData `@Model` instances) keeps this value `Sendable` and
/// safe to cross actor boundaries if needed.
struct SystemHintInput {
    // MARK: Identity / flags

    let agentID: UUID
    let bootstrapComplete: Bool
    let needsCompaction: Bool
    let hasSpaces: Bool

    /// Persisted conversation history up to (but not including) the latest
    /// user turn being sent. Used by sources that make decisions based on
    /// conversation shape (e.g. the hint evaluator).
    let messages: [ChatMessage]

    // MARK: Environment

    /// Snapshot of the current space, if any. `nil` outside a space.
    let space: SpaceSnapshot?
    /// The active space ID for scope-limiting per-turn queries. Kept
    /// separate from ``space`` because sources that reach into scoped
    /// stores (knowledge, calendars) need the identifier itself, not a
    /// display snapshot. `nil` when the chat is not inside a space.
    let spaceID: UUID?
    /// The user's preferred language, if set.
    let language: AppLanguage?
    /// The user's current interaction mode with the agent.
    let mode: InteractionMode
    /// Vocabulary entries (word + aliases) feeding ``VocabularyHintSource``.
    /// Empty for typed turns.
    var vocabulary: [VocabularyEntry] = []

    // MARK: Agent state

    let activeIntents: [IntentSnapshot]
    let activeSkills: [Skill]
    let availableSkills: [Skill]
    /// Capabilities provided by at least one connected, enabled integration.
    var connectedCapabilities: Set<Capability> = []
    /// Capabilities the person said no to connecting (``DeclinedCapabilities``).
    var declinedCapabilities: Set<Capability> = []
    let activeFlow: FlowState?
    /// Notes for active MCP server skills whose server couldn't be reached
    /// this turn (e.g. token expired, server down) — surfaced so the agent
    /// can tell the user rather than silently losing the tools. The skill
    /// stays active; see ``ActiveSkillsSource``.
    var unavailableSkillNotes: [String] = []

    // MARK: Provider & Model

    let provider: ProviderSnapshot
    let modelID: String

    // MARK: Model context

    /// `true` when the active model has a small context window (≤16K) and
    /// needs minimal hydration. Sources check this flag to truncate output.
    /// Small-context models also don't receive tools.
    let isSmallContext: Bool
}
