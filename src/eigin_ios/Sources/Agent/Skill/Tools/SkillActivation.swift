import Foundation

/// Shared mutation for activating a skill on a chat.
///
/// Used by ``ActivateSkillTool`` directly, and by ``StartFlowTool`` as a
/// fallback when a flow's owning skill isn't already active. Callers are
/// responsible for deciding whether activation is appropriate (e.g. checking
/// `isSkillActive`/`alwaysActive` first) — this just performs the mutation.
enum SkillActivation {
    /// Marks an activation as triggered by ``SkillHydrator`` rather than a tool call.
    static let autoActivation = "auto"

    /// Activates `skillID` on `chat`. In small-context mode, deactivates any
    /// other on-demand skill first (single slot: only one on-demand skill
    /// active at a time).
    static func activate(
        skillID: String,
        on chat: Chat,
        activatingToolCallID: String,
        isSmallContext: Bool
    ) {
        if isSmallContext {
            chat.activeSkillEntries.removeAll { entry in
                guard let existing = BundledSkill.skill(forID: entry.skillID) else { return false }
                return !existing.alwaysActive
            }
        }
        chat.activeSkillEntries.append(
            ActiveSkillEntry(
                skillID: skillID,
                activatedAt: .now,
                activatingToolCallID: activatingToolCallID
            )
        )
    }
}
