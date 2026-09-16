import Foundation

/// The user's current interaction mode with the agent.
///
/// Rendered as a section inside the ephemeral `<system_hint>` block so the
/// model can adapt its response style — concise and conversational for live
/// calls, tolerant of transcription noise for dictation, free to use formatting
/// for text.
enum InteractionMode: String {
    case text
    case dictation
    case liveCall
    case headless

    /// Full behavioural guidance for this mode — emitted on first turn of a
    /// session, or whenever the mode changes.
    var fullDescription: String {
        let prompt = switch self {
        case .liveCall: Prompt.Hints.InteractionMode.liveCall
        case .dictation: Prompt.Hints.InteractionMode.dictation
        case .text: Prompt.Hints.InteractionMode.text
        case .headless: Prompt.Hints.InteractionMode.headless
        }
        return prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Short reminder emitted once the mode has already been announced in the
    /// current session, to preserve attention without re-describing the mode.
    var shortReminder: String {
        let prompt = switch self {
        case .liveCall: Prompt.Hints.InteractionMode.liveCallShort
        case .dictation: Prompt.Hints.InteractionMode.dictationShort
        case .text: Prompt.Hints.InteractionMode.textShort
        case .headless: Prompt.Hints.InteractionMode.headlessShort
        }
        return prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
