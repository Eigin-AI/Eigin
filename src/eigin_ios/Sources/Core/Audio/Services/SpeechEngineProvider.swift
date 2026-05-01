/// A TTS engine that can produce speech and list its available voices.
///
/// Each engine (system, Kokoro, future PLAPRE, etc.) conforms to this protocol.
/// The ``SpeechEngineResolver`` iterates registered providers to pick the
/// best available engine for the current locale.
@MainActor
protocol SpeechEngineProvider {
    /// Which engine this provider represents.
    var engineKind: SpeechEngineKind { get }

    /// Languages this engine supports.
    var supportedLanguages: [AppLanguage] { get }

    /// The downloadable asset backing this engine, if any.
    /// `nil` for engines that require no download (e.g. system).
    var asset: (any OnDemandAsset)? { get }

    /// Whether this engine can synthesize speech right now.
    var isReady: Bool { get }

    /// True while this engine is loading its model into memory.
    /// Always `false` for engines with no loading step (e.g. system).
    var isLoadingEngine: Bool { get }

    /// How `DefaultSpeechService` should split text before handing it to
    /// this engine's synthesizer. Engines with persistent multi-utterance
    /// sessions get the historical batching default; engines that restart
    /// per utterance can opt into eager per-sentence chunking.
    var chunkingStrategy: SpeechChunkingStrategy { get }

    /// List available voices with display names, locale, and dialect info.
    func availableVoices(for language: AppLanguage) -> [SpeechVoice]

    /// Create a synthesizer configured for the given voice.
    func makeSynthesizer(voice: SpeechVoice?, language: AppLanguage) -> any SpeechSynthesizing
}

extension SpeechEngineProvider {
    /// Default: preserve historical behavior (paragraph-only one-shot,
    /// 200-char buffered streaming). Engines opt into other strategies by
    /// overriding this property.
    var chunkingStrategy: SpeechChunkingStrategy {
        .buffered
    }
}
