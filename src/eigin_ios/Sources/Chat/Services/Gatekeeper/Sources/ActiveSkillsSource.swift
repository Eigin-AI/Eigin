import Foundation

/// Renders the instruction text for every skill that is currently active.
///
/// Stateless. A skill's `instruction` is typically a short paragraph telling
/// the model what the skill lets it do and when to use it — it belongs in
/// the ephemeral hint rather than the static system prompt so activating a
/// skill mid-session takes effect on the next turn without busting prefix
/// caches. Skipped entirely in compact mode where the budget is too tight.
@MainActor
final class ActiveSkillsSource: SystemHintSource {
    let title = "Active skills"

    func render(_ input: SystemHintInput) async -> String? {
        guard !input.isSmallContext else { return nil }
        guard !input.activeSkills.isEmpty || !input.unavailableSkillNotes.isEmpty
        else { return nil }

        var sections = input.activeSkills
            .map {
                let instruction = $0.instruction
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return "### \($0.displayName)\n\n\(instruction)"
            }

        // An active MCP server skill whose server couldn't be reached this turn
        // stays active (its instructions above still render), but its tools are
        // absent — flag that here so the agent can tell the user, rather than
        // silently failing tool calls.
        sections.append(contentsOf: input.unavailableSkillNotes)

        return sections.joined(separator: "\n\n")
    }
}
