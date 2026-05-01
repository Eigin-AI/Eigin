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

    /// Full behavioural guidance for this mode — emitted on first turn of a
    /// session, or whenever the mode changes.
    var fullDescription: String {
        switch self {
        case .liveCall:
            "The user is in a live voice call. Keep responses brief and conversational. Avoid formatting that doesn't translate to speech. Prefer short, natural sentences."
        case .dictation:
            "The user is dictating via speech-to-text. There may be transcription errors — infer intended meaning from context rather than taking words literally."
        case .text:
            "The user is in text chat. You may use formatting, markdown, lists, and code blocks as appropriate."
        }
    }

    /// Short reminder emitted once the mode has already been announced in the
    /// current session, to preserve attention without re-describing the mode.
    var shortReminder: String {
        switch self {
        case .liveCall:
            "User is in live voice call — keep it brief and conversational."
        case .dictation:
            "User is dictating — expect transcription noise."
        case .text:
            "User is in text chat."
        }
    }
}
