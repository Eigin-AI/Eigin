import AVFoundation

/// Engine provider for Apple's built-in `AVSpeechSynthesizer`.
///
/// Always ready, requires no download. Maps system voices to ``SpeechVoice``.
@Observable
@MainActor
final class SystemEngineProvider: SpeechEngineProvider {
    let engineKind: SpeechEngineKind = .system
    let supportedLanguages: [AppLanguage] = AppLanguage.allCases
    let asset: (any OnDemandAsset)? = nil
    var isReady: Bool {
        true
    }

    var isLoadingEngine: Bool {
        false
    }

    func availableVoices(for language: AppLanguage) -> [SpeechVoice] {
        let prefix = language.voiceLanguagePrefix
        let allVoices = AVSpeechSynthesisVoice.speechVoices()

        // Deduplicate by name, keeping highest quality.
        var bestByName: [String: AVSpeechSynthesisVoice] = [:]
        for voice in allVoices where voice.language.hasPrefix(prefix) {
            if let existing = bestByName[voice.name] {
                if voice.quality.rawValue > existing.quality.rawValue {
                    bestByName[voice.name] = voice
                }
            } else {
                bestByName[voice.name] = voice
            }
        }

        return bestByName.values
            .sorted { $0.quality.rawValue != $1.quality.rawValue
                ? $0.quality.rawValue > $1.quality.rawValue
                : $0.name < $1.name
            }
            .map { voice in
                SpeechVoice(
                    engine: .system,
                    identifier: voice.identifier,
                    displayName: voice.name,
                    languageCode: voice.language,
                    dialect: nil
                )
            }
    }

    func makeSynthesizer(voice: SpeechVoice?, language: AppLanguage) -> any SpeechSynthesizing {
        SystemSpeechSynthesizer(voice: voice, language: language)
    }
}
