/// Identifies a TTS engine backend.
enum SpeechEngineKind: String, Codable {
    /// Apple's built-in `AVSpeechSynthesizer`.
    case system

    /// Pocket TTS local model via FluidAudio CoreML.
    case pocketTTS

    /// Plapre Pico Danish TTS via CoreML.
    case plaprePico
}
