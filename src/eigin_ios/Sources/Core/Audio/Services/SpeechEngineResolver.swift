import Observation

/// Picks the best available TTS engine for the current locale.
///
/// Iterates registered ``SpeechEngineProvider``s in quality order.
/// The first provider that `isReady` and supports the language is used.
/// If a better provider exists but needs a download, it is surfaced
/// via ``upgradeAvailable(for:)`` for the just-in-time download prompt.
@Observable
@MainActor
final class SpeechEngineResolver {
    private let providers: [any SpeechEngineProvider]

    /// - Parameter providers: Engines in preference order (best quality first).
    ///   The last provider should always be ``SystemEngineProvider`` as the fallback.
    init(providers: [any SpeechEngineProvider]) {
        self.providers = providers
    }

    /// Returns the best ready engine for the given language,
    /// creating a synthesizer configured for the given voice.
    func resolve(voice: SpeechVoice?, language: AppLanguage) -> any SpeechSynthesizing {
        let provider = bestReadyProvider(for: language)
        return provider.makeSynthesizer(voice: voice, language: language)
    }

    /// The best engine provider that is ready right now.
    func bestReadyProvider(for language: AppLanguage) -> any SpeechEngineProvider {
        for provider in providers {
            if provider.supportedLanguages.contains(language), provider.isReady {
                return provider
            }
        }
        // System is always the fallback and always ready.
        return providers.last!
    }

    /// If a higher-quality engine is available for download (but not yet ready),
    /// returns its asset. Returns `nil` if the best engine is already ready
    /// or the user has declined the download.
    func upgradeAvailable(for language: AppLanguage) -> (any OnDemandAsset)? {
        let bestReady = bestReadyProvider(for: language)

        for provider in providers {
            guard provider.supportedLanguages.contains(language) else { continue }
            // Found a provider that outranks the current best
            if provider.engineKind != bestReady.engineKind,
               let asset = provider.asset,
               asset.state != .ready,
               !asset.hasBeenDeclined
            {
                return asset
            }
            // If this is the best ready one, stop looking.
            if provider.engineKind == bestReady.engineKind { break }
        }
        return nil
    }

    /// Every downloadable engine asset regardless of language or readiness —
    /// the backing data for the Local assets screen.
    func allAssets() -> [any OnDemandAsset] {
        providers.compactMap(\.asset)
    }

    /// All voices from the best ready engine for a language.
    func voices(for language: AppLanguage) -> [SpeechVoice] {
        bestReadyProvider(for: language).availableVoices(for: language)
    }
}
