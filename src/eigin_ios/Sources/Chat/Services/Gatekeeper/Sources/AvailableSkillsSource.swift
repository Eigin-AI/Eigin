import Foundation

/// Lists skills the agent can activate on demand (excluding always-active and
/// already-active skills).
///
/// Stateless. In compact mode the list is truncated to the top entries and
/// each description is clipped, since small-context models can't afford a
/// long catalog in every turn.
@MainActor
final class AvailableSkillsSource: SystemHintSource {
    let title = "Available skills"

    /// Maximum number of skills listed in compact mode.
    private let compactLimit = 5
    /// Character cap applied to each skill's description in compact mode.
    private let compactDescriptionLimit = 60

    func render(_ input: SystemHintInput) async -> String? {
        guard !input.isSmallContext else { return nil }
        let activeIDs = Set(input.activeSkills.map(\.id))
        let activatable = input.availableSkills.filter { skill in
            guard !skill.alwaysActive, !activeIDs.contains(skill.id) else { return false }
            // Hide tool-less skills until their required capability is connected.
            if skill.requiredTools.isEmpty, !skill.requiredCapabilities.isEmpty {
                return !skill.requiredCapabilities.isDisjoint(with: input.connectedCapabilities)
            }
            return true
        }
        guard !activatable.isEmpty else { return nil }

        let shown = input.isSmallContext
            ? Array(activatable.prefix(compactLimit))
            : activatable

        let lines: [String] = shown.map { skill in
            let description: String = if input.isSmallContext,
                                         skill.smallInstruction.count > compactDescriptionLimit
            {
                String(skill.smallInstruction.prefix(compactDescriptionLimit)) + "…"
            } else {
                skill.smallInstruction
            }
            return "- \(skill.displayName) (`\(skill.id)`): \(description)"
        }

        let skillList = lines.joined(separator: "\n")
        return Prompt.Hints.availableSkills(skills: skillList)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
