import Foundation

/// Renders the current space's name and per-space instructions, if any.
///
/// Stateless. In compact mode the instructions are truncated to a short cap so
/// the space context is still present without consuming a large chunk of the
/// small-model's hydration budget.
@MainActor
final class SpaceSource: SystemHintSource {
    let title = "Space"

    /// Character cap applied to space instructions in compact mode.
    private let compactInstructionsLimit = 120

    func render(_ input: SystemHintInput) async -> String? {
        guard let space = input.space, !space.instructions.isEmpty else { return nil }

        let instructions = input.isSmallContext && space.instructions
            .count > compactInstructionsLimit
            ? String(space.instructions.prefix(compactInstructionsLimit)) + "…"
            : space.instructions

        return Prompt.Hints.space(name: space.name, instructions: instructions)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
