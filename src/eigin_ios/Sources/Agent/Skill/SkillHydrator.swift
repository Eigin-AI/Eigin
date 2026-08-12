import Foundation

/// Matches a user message against curated per-skill trigger keywords — deterministic
/// keyword matching, not embeddings or an LLM classifier, so it's zero-latency and
/// conservative about firing.
enum SkillHydrator {
    /// Returns the IDs of `candidates` to auto-activate for `userText`, ordered by
    /// distinct trigger-hit count (ties broken by candidate order), capped at `cap`.
    ///
    /// `candidates` must already be filtered to on-demand, not-already-active,
    /// capability-satisfied skills — see ``SkillCatalog/activatable``.
    static func matches(userText: String, candidates: [Skill], cap: Int = 2) -> [String] {
        guard !candidates.isEmpty else { return [] }
        let messageTokens = MessageTokenizer.tokenize(userText)
        guard !messageTokens.isEmpty else { return [] }

        let scored: [(id: String, hits: Int)] = candidates.compactMap { skill in
            // The skill's own display name is an implicit trigger — it's already
            // localized to the app's current language, so this catches a literal
            // mention ("health", "Sundhed", …) without curating it into every
            // skill's trigger list by hand.
            let triggers = skill.triggers.all.union(MessageTokenizer.tokenize(skill.displayName))
            let hits = triggers.intersection(messageTokens).count
            return hits > 0 ? (skill.id, hits) : nil
        }
        guard !scored.isEmpty else { return [] }

        // Stable sort: Array.sorted is stable in Swift, so equal-hit candidates keep
        // their original (candidate) order.
        return scored
            .sorted { $0.hits > $1.hits }
            .prefix(cap)
            .map(\.id)
    }
}
