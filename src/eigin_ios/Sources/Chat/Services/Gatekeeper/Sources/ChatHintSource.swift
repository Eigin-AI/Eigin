import Foundation

/// Surfaces a gentle per-turn hint from the ``HintCatalog``.
///
/// Each hint controls its own conditions, including whether it applies to
/// reactive agents. The per-hint cooldowns (persisted in ``HintHistory``) are
/// what keep hints from repeating.
@MainActor
final class ChatHintSource: SystemHintSource {
    let title = "Hint"

    private let initiative: ProactivityLevel

    init(proactivity: ProactivityLevel) {
        initiative = proactivity
    }

    func render(_ input: SystemHintInput) async -> String? {
        ChatHint.evaluate(
            agentID: input.agentID,
            bootstrapComplete: input.bootstrapComplete,
            messages: input.messages,
            hasSpaces: input.hasSpaces,
            needsCompaction: input.needsCompaction,
            initiative: initiative
        )
    }
}
