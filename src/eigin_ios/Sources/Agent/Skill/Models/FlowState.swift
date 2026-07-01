import Foundation

/// Tracks progress through an active, staged flow within a chat.
///
/// Flows drip-feed a skill's instructions one stage at a time via
/// `start_flow`/`advance_flow`, instead of front-loading everything into the
/// skill's system prompt. See ``BundledSkill/planning`` for the first flow.
struct FlowState: Codable, Equatable {
    /// The ID of the active flow (globally unique across skills).
    let flowID: String

    /// The ID of the skill that owns this flow.
    let skillID: String

    /// Index into the flow's ordered stage list.
    var stage: Int

    /// Notes the model has recorded while advancing through the flow, in order.
    var notes: [String]
}
