import Foundation

/// Renders the agent's currently active intents (goals it's pursuing).
///
/// Stateless. Intents arrive ordered by temporal relevance from
/// ``IntentService``; this source formats them as a bulleted list and appends a
/// short cue when something is timely ("due today", "in 3 days", "2 open
/// tasks"), so the agent sees why an intent is rising. In compact mode the list
/// is truncated to the top three intents and each intent renders as a single
/// truncated line to fit the limited hydration budget of small-context models.
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
            if input.isSmallContext {
                // Small-context models get a minimal one-liner.
                let content = intent.content.count > compactContentLimit
                    ? String(intent.content.prefix(compactContentLimit)) + "…"
                    : intent.content
                return "- \"\(content)\""
            }

            // Full context: ID so the agent can act on the intent via tools,
            // a timeliness cue, and any open tasks.
            var line = "- [\(intent.id.uuidString)] \"\(intent.content)\""
            if let cue = IntentDigest.summary(for: intent) {
                line += " (\(cue))"
            }
            let pending = intent.tasks.filter { !$0.completed }
            if !pending.isEmpty {
                let taskLines = pending.map { task -> String in
                    let label = task.content.count > 50
                        ? task.content.prefix(50) + "…"
                        : Substring(task.content)
                    return "  • \(label)"
                }
                line += "\n" + taskLines.joined(separator: "\n")
            }
            return line
        }

        return lines.joined(separator: "\n")
    }
}
