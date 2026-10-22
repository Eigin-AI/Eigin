import Factory
import Foundation
import NaturalLanguage

/// Hints the skills most relevant to the current conversation.
///
/// The last few messages are embedded and matched against skill descriptors
/// (``SkillIndex``); the top matches render as compact hint lines — name +
/// one-line description. When retrieval finds nothing above threshold, no
/// skill section renders. When retrieval is unavailable (model assets
/// missing) and no exact name match anchors the context, a capped list of
/// the catalog appears instead.
@MainActor
final class AvailableSkillsSource: SystemHintSource {
    let title = "Available skills"

    /// Maximum entries in the fallback list.
    private let fallbackLimit = 20

    /// Maximum sentence parts scored per turn.
    private let maxQueryParts = 4

    private let skillIndex: any SkillIndexing

    init(skillIndex: any SkillIndexing = Container.shared.skillIndex()) {
        self.skillIndex = skillIndex
    }

    func render(_ input: SystemHintInput) async -> String? {
        guard !input.isSmallContext else { return nil }
        let activatable = SkillCatalog.activatable(
            from: input.availableSkills,
            activeIDs: Set(input.activeSkills.map(\.id)),
            connectedCapabilities: input.connectedCapabilities,
            declined: input.declinedCapabilities
        )
        guard !activatable.isEmpty else { return nil }

        let context = input.messages.suffix(3).compactMap(\.content).joined(separator: "\n")
        let matches = await skillIndex.search(
            queryParts: queryParts(from: context),
            among: activatable,
            threshold: SkillIndex.matchThreshold,
            limit: SkillIndex.resultLimit
        )

        // Retrieval unavailable (or nothing to embed): capped full list.
        // Retrieval worked but nothing fit: no section at all.
        let skills: String
        if let matches, !context.isEmpty, !matches.isEmpty {
            skills = matches
                .map { line(for: $0.skill, connected: input.connectedCapabilities) }
                .joined(separator: "\n")
        } else if matches != nil {
            return nil
        } else {
            skills = fallbackList(activatable, connected: input.connectedCapabilities)
        }

        return Prompt.Hints.availableSkills(skills: skills)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Sentences of the recent conversation. Each is embedded and scored
    /// against the descriptors separately — a skill's score is its
    /// best-matching sentence, so one on-topic sentence isn't averaged away by
    /// its multi-topic surroundings.
    private func queryParts(from context: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = context
        var sentences: [String] = []
        tokenizer.enumerateTokens(in: context.startIndex ..< context.endIndex) { range, _ in
            let sentence = String(context[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty {
                sentences.append(sentence)
            }
            return true
        }
        // Beyond this many sentences, the best match is rarely in the tail.
        let parts = sentences.prefix(maxQueryParts)
        return parts.isEmpty ? [context] : Array(parts)
    }

    /// One hint line. A skill that needs connecting is phrased as what
    /// activation does, so the model offers it rather than reports it.
    private func line(for skill: Skill, connected: Set<Capability>) -> String {
        let base = "- \(skill.displayName) (`\(skill.id)`): \(skill.summaryLine)"
        guard let needed = SkillCatalog.connectionNeeded(for: skill, connected: connected)
        else { return base }
        return "\(base) (activating asks to connect \(needed))"
    }

    /// The capped full list, with a pointer to `search_skills` for overflow.
    private func fallbackList(_ activatable: [Skill], connected: Set<Capability>) -> String {
        let shown = activatable.prefix(fallbackLimit)
        var lines = shown.map { line(for: $0, connected: connected) }
        let remaining = activatable.count - shown.count
        if remaining > 0 {
            lines.append("…\(remaining) more skills available — call `search_skills` to find one.")
        }
        return lines.joined(separator: "\n")
    }
}
