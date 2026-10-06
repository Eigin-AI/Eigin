import Foundation

/// Records a skill activation within a chat, anchoring it in time and message history.
///
/// Used by the skill lifetime system (42F-6). Skills stay active for the life of the
/// chat, including across conversation compaction.
struct ActiveSkillEntry: Codable, Equatable {
    /// The ID of the activated skill (matches ``Skill/id``).
    let skillID: String

    /// When the skill was activated.
    let activatedAt: Date

    /// The tool call ID from the `activate_skill` invocation.
    /// Can be used to locate the assistant message in persisted history,
    /// since tool call IDs are stored in ``Message/toolCallsData``.
    let activatingToolCallID: String
}
