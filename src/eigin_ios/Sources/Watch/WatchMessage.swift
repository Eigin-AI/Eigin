import Foundation

/// The wire vocabulary shared by the watch app and the phone.
///
/// Compiled into both targets rather than shared through a module — the same
/// arrangement the widget extension uses for the files it needs.
enum WatchMessage {
    static let actionKey = "action"
    static let statusKey = "status"

    /// Asks the phone to answer a question dictated on the watch, carried as
    /// file-transfer metadata.
    static let ask = "ask"
    /// Wakes the phone ahead of an audio transfer. A file transfer alone is
    /// delivered opportunistically and does not launch a suspended app.
    static let audioIncoming = "audioIncoming"
    /// The agent's reply coming back.
    static let replyKey = "reply"
    static let errorKey = "error"
    /// The turn is complete, sent from the phone once it is done. The reply
    /// itself arrives as a notification; this is the watch's completion cue.
    static let answer = "answer"

    /// The phone woke and accepted the request. Says nothing about whether the
    /// turn went on to finish.
    static let woke = "woke"
    static let unknownAction = "unknownAction"
}
