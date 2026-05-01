import Foundation

extension Agent {
    /// Returns the agent's voice as a ``SpeechVoice``, or `nil` for the language default.
    ///
    /// Currently bridges the legacy `voiceIdentifier` string to the new type.
    var voice: SpeechVoice? {
        guard let id = voiceIdentifier, !id.isEmpty else { return nil }
        return SpeechVoice(
            engine: .system,
            identifier: id,
            displayName: "",
            languageCode: "",
            dialect: nil
        )
    }
}
