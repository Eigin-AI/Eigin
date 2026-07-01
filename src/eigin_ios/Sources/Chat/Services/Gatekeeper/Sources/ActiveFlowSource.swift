import Foundation

/// Renders the current stage of the active flow, if any, as a persistent
/// per-turn reminder.
///
/// A flow's stage instructions are also returned directly by `start_flow`/
/// `advance_flow`'s tool results, but a tool result is a single message
/// that gets buried as the conversation continues. This source keeps the
/// same instructions in front of the model on every subsequent turn until
/// it calls `advance_flow` again, so a long conversation can't cause it to
/// lose track of which stage it's in. Skipped entirely in compact mode.
@MainActor
final class ActiveFlowSource: SystemHintSource {
    let title = "Active flow"

    func render(_ input: SystemHintInput) async -> String? {
        guard !input.isSmallContext else { return nil }
        guard let state = input.activeFlow,
              let flow = FlowRegistry.all[state.flowID] else { return nil }
        guard state.stage < flow.stages.count else { return nil }
        let stage = flow.stages[state.stage]

        return """
        You're in the middle of the "\(flow.name)" flow, stage \(state.stage + 1) of \(flow.stages
            .count) ("\(stage.name)"). \
        Follow these instructions, and call \
        advance_flow once you're ready to move on:

        \(stage.instructions(notes: state.notes))
        """
    }
}
