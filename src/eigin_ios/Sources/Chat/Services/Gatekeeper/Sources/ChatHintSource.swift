import Foundation

/// Surfaces a gentle per-turn hint from the ``HintCatalog``.
///
/// Gated on proactivity: reactive agents never receive hints. For any other
/// proactivity level, a hint is shown whenever its condition is satisfied
/// and its cooldown has elapsed — the per-hint cooldowns (persisted in
/// ``HintHistory``) are what keep hints from repeating.
@MainActor
final class ChatHintSource: SystemHintSource {
    let title = "Hint"

    private let isEnabled: Bool

    init(proactivity: ProactivityLevel) {
        isEnabled = proactivity != .reactive
    }

    func render(_ input: SystemHintInput) async -> String? {
        guard isEnabled else { return nil }
        return ChatHint.evaluate(
            agentID: input.agentID,
            bootstrapComplete: input.bootstrapComplete,
            messages: input.messages,
            hasSpaces: input.hasSpaces,
            needsCompaction: input.needsCompaction
        )
    }
}
