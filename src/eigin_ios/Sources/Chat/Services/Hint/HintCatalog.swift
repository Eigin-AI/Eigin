import Foundation

/// A single hint definition: what to say, when it's relevant, and how often.
struct HintType {
    let id: String
    let cooldown: TimeInterval
    let priority: Int
    let condition: @Sendable (HintContext) -> Bool
    let template: @Sendable (HintContext) -> String
}

/// Snapshot of agent/chat state passed to hint conditions and templates.
struct HintContext {
    let messages: [ChatMessage]
    let hasSpaces: Bool
    let needsCompaction: Bool
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
    ]

    // MARK: - Hint Definitions

    /// Periodically encourage the agent to revisit user/identity core docs.
    static let revisitCoreDocs = HintType(
        id: "revisit_core_docs",
        cooldown: 3 * 86400, // 3 days
        priority: 5,
        condition: { _ in true },
        template: { _ in
            """
            It might be a good time to revisit what you know about the user and about yourself. \
            Read through your user core and identity core — is there anything new you've learned \
            that should be added, or anything that feels outdated? Update them if it feels right. \
            No rush, and no need to announce it.
            """
        }
    )

    /// Nudge the agent to save concrete details from the conversation as knowledge.
    static let collectKnowledge = HintType(
        id: "collect_knowledge",
        cooldown: 86400, // 1 day
        priority: 6,
        condition: { ctx in ctx.messages.count >= 6 },
        template: { _ in
            """
            If the user has mentioned anything concrete in this conversation — a name, preference, \
            opinion, relationship, job, location, interest, or other specific detail — that isn't \
            already in your knowledge base, save each detail as its own fact or note linked to the \
            relevant actor or thing. Prefer creating new entries over updating existing ones.
            """
        }
    )

    /// Suggest the agent check in with the user about their setup preferences.
    static let selfConfigure = HintType(
        id: "self_configure",
        cooldown: 7 * 86400, // 7 days
        priority: 3,
        condition: { _ in true },
        template: { _ in
            """
            You can configure aspects of yourself — your name, voice, personality, how proactive \
            you are. If it feels natural, you could check in with the user about whether everything \
            is working well for them, or if they'd like to adjust anything. Only if it fits the moment.
            """
        }
    )

    /// Warn when the conversation is approaching auto-compaction.
    static let compactionWarning = HintType(
        id: "compaction_warning",
        cooldown: 0, // no cooldown — fires whenever relevant
        priority: 10,
        condition: { ctx in ctx.needsCompaction },
        template: { _ in
            """
            This conversation is getting long and will be automatically summarised soon. \
            If there's anything important the user might want you to remember across conversations, \
            now would be a good time to ask — or save it to your knowledge yourself if you already know.
            """
        }
    )

    /// Suggest spaces for users who don't have any yet.
    static let capabilitySpaces = HintType(
        id: "capability_spaces",
        cooldown: 14 * 86400, // 14 days
        priority: 1,
        condition: { ctx in !ctx.hasSpaces },
        template: { _ in
            """
            The user can create focused spaces for different projects or topics, each with their \
            own context and instructions. If the user seems to have a recurring topic that would \
            benefit from dedicated context, you could mention this. Only if relevant.
            """
        }
    )
}
