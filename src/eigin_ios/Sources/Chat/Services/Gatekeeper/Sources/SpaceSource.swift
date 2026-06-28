import Foundation

/// Renders the current space's name and per-space instructions, if any.
///
/// Stateless. Skipped in compact mode — small-context models cannot afford
/// arbitrary per-space guidance in every turn.
@MainActor
final class SpaceSource: SystemHintSource {
    let title = "Space"

    func render(_ input: SystemHintInput) async -> String? {
        guard !input.isSmallContext else { return nil }
        guard let space = input.space, !space.instructions.isEmpty else { return nil }

        return Prompt.Hints.space(name: space.name, instructions: space.instructions)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
