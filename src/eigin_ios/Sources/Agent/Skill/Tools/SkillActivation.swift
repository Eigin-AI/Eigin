import Foundation

/// Shared mutation for activating a skill on a chat.
///
/// Used by ``ActivateSkillTool`` directly, and by ``StartFlowTool`` as a
/// fallback when a flow's owning skill isn't already active. Callers are
/// responsible for deciding whether activation is appropriate (e.g. checking
/// `isSkillActive`/`alwaysActive` first) — this just performs the mutation.
enum SkillActivation {
    /// Activates `skillID` on `chat`, replacing any existing entry for it.
    static func activate(
        skillID: String,
        on chat: Chat,
        activatingToolCallID: String
    ) {
        chat.activeSkillEntries.removeAll { $0.skillID == skillID }
        chat.activeSkillEntries.append(
            ActiveSkillEntry(
                skillID: skillID,
                activatedAt: .now,
                activatingToolCallID: activatingToolCallID
            )
        )
    }
}
