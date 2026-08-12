import Foundation

/// A packaged capability the agent can activate on demand.
///
/// Skills bundle instructions (injected into the system prompt when active)
/// with the tools they require. The active tool set is the union of all
/// active skills' ``requiredTools``.
struct Skill: Identifiable {
    let id: String
    let displayName: String
    let description: String
    let instruction: String
    /// Short instruction for small on-device models (~1-2 sentences).
    var smallInstruction: String = ""
    let requiredTools: Set<ToolCapability>
    /// Capabilities this skill needs from a connected integration (e.g. `.email`).
    /// Empty for skills that only use built-in tools.
    var requiredCapabilities: Set<Capability> = []
    let alwaysActive: Bool
    /// Keyword triggers that eagerly activate this skill from the user's message.
    /// Empty for always-active skills and skills not yet wired for auto-activation.
    var triggers: SkillTriggers = .init()
}

/// Keyword triggers for eager, same-turn skill activation (see ``SkillHydrator``).
///
/// Tokens are grouped **by language** for readable authoring, but matching always
/// reads the flattened ``all`` union — the grouping costs nothing at runtime and
/// exists purely to keep a growing multilingual list organised.
struct SkillTriggers {
    /// Tokens grouped by the language they belong to.
    var byLanguage: [AppLanguage: Set<String>] = [:]
    /// Language-neutral tokens (brand/loanwords like "gmail", "aula").
    var shared: Set<String> = []

    /// Flattened union of every trigger token, used for matching.
    var all: Set<String> {
        byLanguage.values.reduce(into: shared) { $0.formUnion($1) }
    }
}

// MARK: - Hashable (identity = id)

extension Skill: Hashable {
    static func == (lhs: Skill, rhs: Skill) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
