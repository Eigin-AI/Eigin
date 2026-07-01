import Foundation

/// A staged flow, declared in a skill's `flows.toml` manifest and compiled by
/// `eigin-tools` into ``FlowRegistry``.
struct FlowDefinition: Sendable {
    let name: String
    let skillID: String
    let stages: [FlowStageDefinition]
}

/// A single stage within a ``FlowDefinition``.
struct FlowStageDefinition: Sendable {
    let name: String
    /// Renders this stage's instruction prose (compiled from its `.jinja` file).
    let render: @Sendable () -> String
    /// Whether `advance_flow`'s accumulated notes should be appended when this
    /// stage's instructions are returned.
    let showNotes: Bool

    /// This stage's instructions, with the accumulated notes recap appended
    /// when ``showNotes`` is set. Shared by ``AdvanceFlowTool`` and
    /// ``ActiveFlowSource`` so the tool result and the persistent hint stay
    /// in sync.
    func instructions(notes: [String]) -> String {
        guard showNotes, !notes.isEmpty else { return render() }
        let recap = notes.map { "- \($0)" }.joined(separator: "\n")
        return "\(render())\n\nWhat you've learned so far in this flow:\n\(recap)"
    }
}
