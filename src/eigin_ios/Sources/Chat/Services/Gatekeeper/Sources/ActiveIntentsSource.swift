import Foundation

/// Renders the agent's currently active intents (goals it's pursuing).
///
/// Stateless. Intents arrive ordered by temporal relevance from
/// ``IntentService``; this source formats them as a bulleted list and appends a
/// short cue when something is timely ("due today", "in 3 days", "2 open
/// tasks"), so the agent sees why an intent is rising. In compact mode the list
/// is truncated to the top three intents and each intent's content is clipped,
/// to fit into the limited hydration budget of small-context models.
@MainActor
final class ActiveIntentsSource: SystemHintSource {
    let title = "Active intents"

    /// Maximum number of intents rendered in compact mode.
    private let compactLimit = 3
    /// Character cap applied to each intent's content in compact mode.
    private let compactContentLimit = 80

    func render(_ input: SystemHintInput) async -> String? {
        guard !input.activeIntents.isEmpty else { return nil }

        let intents = input.isSmallContext
            ? Array(input.activeIntents.prefix(compactLimit))
            : input.activeIntents

        let lines: [String] = intents.map { intent in
            let content: String = if input.isSmallContext,
                                     intent.content.count > compactContentLimit
            {
                String(intent.content.prefix(compactContentLimit)) + "…"
            } else {
                intent.content
            }
            // Full id so the agent can act on the intent directly via tools.
            var line = "- [\(intent.id.uuidString)] \"\(content)\""
            if let cue = IntentDigest.summary(for: intent) {
                line += " (\(cue))"
            }
            return line
        }

        return lines.joined(separator: "\n")
    }
}
