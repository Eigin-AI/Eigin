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
            !skill.alwaysActive && !activeIDs.contains(skill.id)
        }
        guard !activatable.isEmpty else { return nil }

        let shown = input.isSmallContext
            ? Array(activatable.prefix(compactLimit))
            : activatable

        let lines: [String] = shown.map { skill in
            let description: String = if input.isSmallContext,
                                         skill.description.count > compactDescriptionLimit
            {
                String(skill.description.prefix(compactDescriptionLimit)) + "…"
            } else {
                skill.description
            }
            return "- \(skill.displayName) (`\(skill.id)`): \(description)"
        }

        var body = lines.joined(separator: "\n")
        if !input.isSmallContext {
            // Cloud-backed models do fine with natural-language instructions
            // like this. Small local models are triggered by the native tool
            // declarations in the system turn and by the explicit format
            // instruction in the system prompt — a markdown mention of
            // `activate_skill` here risks the model emitting it as text
            // instead of calling it.
            body += "\n\nUse `activate_skill` to enable a skill when you need its tools."
        }
        return body
    }
}
