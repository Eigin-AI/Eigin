import AVFoundation
import Observation

/// A voice installed on the device, discovered from AVSpeechSynthesisVoice.
struct InstalledVoice: Identifiable {
    let id: String // AVSpeechSynthesisVoice.identifier
    let name: String // e.g. "Samantha"
    let language: String // e.g. "en-US"
    let quality: AVSpeechSynthesisVoiceQuality
}

/// Dynamic voice discovery based on what's installed on the device.
@MainActor
protocol VoiceService {
    var installedVoices: [InstalledVoice] { get }
    var recommendedVoices: [InstalledVoice] { get }
    var otherVoices: [InstalledVoice] { get }
    func voice(for identifier: String) -> AVSpeechSynthesisVoice?
    func bestIdentifier(forName name: String) -> String?
    func voices(for language: AppLanguage)
        -> (recommended: [InstalledVoice], other: [InstalledVoice])
    /// Engine-aware voice list for the voice picker UI.
    func availableSpeechVoices(for language: AppLanguage) -> [SpeechVoice]
    /// Downloadable asset if a better engine is available but not yet downloaded.
    func upgradeAsset(for language: AppLanguage) -> (any OnDemandAsset)?
    /// Whether the best engine is a local model (not system).
    func isUsingEnhancedEngine(for language: AppLanguage) -> Bool
    func refresh()
}

/// Default implementation that queries AVSpeechSynthesisVoice.speechVoices()
/// and delegates to the ``SpeechEngineResolver`` when available.
@Observable
final class DefaultVoiceService: VoiceService {
    private(set) var installedVoices: [InstalledVoice] = []
    private(set) var recommendedVoices: [InstalledVoice] = []
    private(set) var otherVoices: [InstalledVoice] = []

    /// When set, voice queries prefer the resolver's best engine.
    var resolver: SpeechEngineResolver?

    init() {
        refresh()
    }

    func voice(for identifier: String) -> AVSpeechSynthesisVoice? {
        guard !identifier.isEmpty else { return nil }
        return AVSpeechSynthesisVoice(identifier: identifier)
    }

    /// Resolves a display name (e.g. "Alba" or "Samantha") to the best identifier.
    /// Checks resolver voices first, then system voices.
    func bestIdentifier(forName name: String) -> String? {
        if let resolver {
            let language = LanguageManager().currentLanguage
            let resolverVoices = resolver.voices(for: language)
            if let match = resolverVoices.first(where: {
                $0.displayName.caseInsensitiveCompare(name) == .orderedSame
            }) {
                return match.identifier
            }
        }
        // Fallback: system voices
        let matching = installedVoices.filter { $0.name.lowercased() == name.lowercased() }
        return matching.sorted(by: { $0.quality.rawValue > $1.quality.rawValue }).first?.id
    }

    func voices(for language: AppLanguage)
        -> (recommended: [InstalledVoice], other: [InstalledVoice])
    {
        // If the resolver has a non-system engine ready, return its voices as recommended.
        if let resolver {
            let provider = resolver.bestReadyProvider(for: language)
            if provider.engineKind != .system {
                let engineVoices = provider.availableVoices(for: language).map { v in
                    InstalledVoice(
                        id: v.identifier,
                        name: v.displayName,
                        language: v.languageCode,
                        quality: .enhanced
                    )
                }
                return (recommended: engineVoices, other: [])
            }
        }

        // System voice fallback
        let prefix = language.voiceLanguagePrefix
        var bestByName: [String: InstalledVoice] = [:]
        for voice in installedVoices where voice.language.hasPrefix(prefix) {
            if let existing = bestByName[voice.name] {
                if voice.quality.rawValue > existing.quality.rawValue {
                    bestByName[voice.name] = voice
                }
            } else {
                bestByName[voice.name] = voice
            }
        }
        let deduped = Array(bestByName.values)
        let recommended = deduped
            .filter { $0.quality.rawValue >= AVSpeechSynthesisVoiceQuality.enhanced.rawValue }
            .sorted(by: {
                $0.quality.rawValue != $1.quality.rawValue ? $0.quality.rawValue > $1.quality
                    .rawValue : $0.name < $1
                    .name
            })
        let recommendedIDs = Set(recommended.map(\.id))
        let other = deduped
            .filter { !recommendedIDs.contains($0.id) }
            .sorted(by: { $0.name < $1.name })
        return (recommended, other)
    }

    func availableSpeechVoices(for language: AppLanguage) -> [SpeechVoice] {
        if let resolver {
            return resolver.voices(for: language)
        }
        let (recommended, other) = voices(for: language)
        return (recommended + other).map { v in
            SpeechVoice(
                engine: .system,
                identifier: v.id,
                displayName: v.name,
                languageCode: v.language,
                dialect: nil
            )
        }
    }

    func upgradeAsset(for language: AppLanguage) -> (any OnDemandAsset)? {
        resolver?.upgradeAvailable(for: language)
    }

    func isUsingEnhancedEngine(for language: AppLanguage) -> Bool {
        guard let resolver else { return false }
        return resolver.bestReadyProvider(for: language).engineKind != .system
    }

    func refresh() {
        let allVoices = AVSpeechSynthesisVoice.speechVoices()
        installedVoices = allVoices.map { voice in
            InstalledVoice(
                id: voice.identifier,
                name: voice.name,
                language: voice.language,
                quality: voice.quality
            )
        }

        var bestByName: [String: InstalledVoice] = [:]
        for voice in installedVoices {
            if let existing = bestByName[voice.name] {
                if voice.quality.rawValue > existing.quality.rawValue {
                    bestByName[voice.name] = voice
                }
            } else {
                bestByName[voice.name] = voice
            }
        }
        let deduped = Array(bestByName.values)

        let highQualityEnglish = deduped.filter {
            $0.language.hasPrefix("en") && $0.quality.rawValue >= AVSpeechSynthesisVoiceQuality
                .enhanced.rawValue
        }
        recommendedVoices = highQualityEnglish
            .sorted(by: {
                $0.quality.rawValue != $1.quality.rawValue ? $0.quality.rawValue > $1.quality
                    .rawValue : $0.name < $1
                    .name
            })

        let recommendedIDs = Set(recommendedVoices.map(\.id))
        otherVoices = deduped
            .filter { !recommendedIDs.contains($0.id) }
            .sorted(by: { $0.name < $1.name })
    }
}

/// Preview stub that returns no voices.
struct PreviewVoiceService: VoiceService {
    var installedVoices: [InstalledVoice] {
        []
    }

    var recommendedVoices: [InstalledVoice] {
        []
    }

    var otherVoices: [InstalledVoice] {
        []
    }

    func voice(for identifier: String) -> AVSpeechSynthesisVoice? {
        nil
    }

    func bestIdentifier(forName name: String) -> String? {
        nil
    }

    func voices(for language: AppLanguage)
        -> (recommended: [InstalledVoice], other: [InstalledVoice])
    {
        ([], [])
    }

    func availableSpeechVoices(for language: AppLanguage) -> [SpeechVoice] {
        []
    }

    func upgradeAsset(for language: AppLanguage) -> (any OnDemandAsset)? {
        nil
    }

    func isUsingEnhancedEngine(for language: AppLanguage) -> Bool {
        false
    }

    func refresh() {}
}
