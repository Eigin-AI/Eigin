#if !targetEnvironment(simulator)
import Foundation

/// Engine provider for Plapre Pico Danish TTS via CoreML.
///
/// Surfaces the model in the Voice Engine settings via ``PlaprePicoModelManager``
/// so users can trigger the download. `isReady` is currently hard-wired to `false`
/// until the inference layer is wired up — meaning Danish synthesis still falls
/// through to the system engine even after the asset is installed. This will
/// flip to `modelManager.isDownloaded` once `PlaprePicoSession` lands.
@Observable
@MainActor
final class PlaprePicoEngineProvider: SpeechEngineProvider {
    let engineKind: SpeechEngineKind = .plaprePico
    let supportedLanguages: [AppLanguage] = [.danish]

    var asset: (any OnDemandAsset)? {
        modelManager
    }

    var isReady: Bool {
        modelManager.isDownloaded
    }

    var isLoadingEngine: Bool {
        modelManager.isLoading
    }

    /// Plapre's decoder restarts per utterance, so per-sentence chunks give
    /// the most natural pacing and the most stable autoregressive output.
    let chunkingStrategy: SpeechChunkingStrategy = .eager

    let modelManager: PlaprePicoModelManager

    init(modelManager: PlaprePicoModelManager) {
        self.modelManager = modelManager
    }

    func availableVoices(for language: AppLanguage) -> [SpeechVoice] {
        guard language == .danish else { return [] }
        return PlaprePicoConfig.speakers.map { id in
            SpeechVoice(
                engine: .plaprePico,
                identifier: id,
                displayName: id.capitalized,
                languageCode: "da-DK",
                dialect: nil
            )
        }
    }

    func makeSynthesizer(voice: SpeechVoice?, language: AppLanguage) -> any SpeechSynthesizing {
        let voiceID = voice?.identifier ?? PlaprePicoConfig.defaultSpeaker
        return PlaprePicoSpeechSynthesizer(modelManager: modelManager, voiceName: voiceID)
    }
}
#endif
