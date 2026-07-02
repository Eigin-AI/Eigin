import Foundation

/// App-wide language preference. Controls dictation locale, TTS voice fallback, and UI
/// localization.
enum AppLanguage: String, CaseIterable, Codable {
    case english = "en"
    case danish = "da"

    var displayName: String {
        switch self {
        case .english: "English"
        case .danish: "Dansk"
        }
    }

    /// BCP-47 locale identifier for speech recognition (e.g. `"da-DK"`).
    var speechLocaleIdentifier: String {
        switch self {
        case .english: "en-US"
        case .danish: "da-DK"
        }
    }

    /// Prefix used to filter `AVSpeechSynthesisVoice.language` (e.g. `"da"`).
    var voiceLanguagePrefix: String {
        rawValue
    }

    /// The language currently selected app-wide, read from the same persisted
    /// preference `Bundle.appLanguage` uses. Defaults to `.english`.
    static var current: AppLanguage {
        UserDefaults.standard.string(forKey: StorageKey.appLanguage)
            .flatMap(AppLanguage.init(rawValue:)) ?? .english
    }

    // MARK: - Detection

    /// Returns the first supported app language matching the given preferred language
    /// identifiers, or `nil` if none are supported. Defaults to the device's
    /// `Locale.preferredLanguages`.
    static func detectedFromSystem(
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> AppLanguage? {
        for identifier in preferredLanguages {
            let code = identifier.split(separator: "-").first.map(String.init) ?? identifier
            if let language = AppLanguage(rawValue: code) {
                return language
            }
        }
        return nil
    }
}
