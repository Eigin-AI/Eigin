import Foundation

/// Engine-agnostic voice reference.
///
/// Each TTS engine defines its own voices. This struct provides
/// a uniform representation for storage, selection, and display.
struct SpeechVoice: Codable, Equatable, Identifiable {
    /// Which engine this voice belongs to.
    let engine: SpeechEngineKind

    /// Engine-specific identifier (e.g. AV voice ID or Kokoro style name like `"af_heart"`).
    let identifier: String

    /// User-facing name (e.g. "Heart", "Samantha").
    let displayName: String

    /// BCP-47 language code (e.g. "en-US", "da-DK").
    let languageCode: String

    /// Optional dialect label (e.g. "American", "British").
    let dialect: String?

    var id: String {
        "\(engine.rawValue):\(identifier)"
    }
}
