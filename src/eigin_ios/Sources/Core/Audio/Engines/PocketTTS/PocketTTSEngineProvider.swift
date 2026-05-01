#if !targetEnvironment(simulator)
import FluidAudio
import Foundation

/// Engine provider for Pocket TTS via FluidAudio CoreML.
///
/// Only ready when the model has been downloaded via ``PocketTTSModelManager``.
/// Supports English with the "alba" voice.
@Observable
@MainActor
final class PocketTTSEngineProvider: SpeechEngineProvider {
    let engineKind: SpeechEngineKind = .pocketTTS
    let supportedLanguages: [AppLanguage] = [.english]

    var asset: (any OnDemandAsset)? {
        modelManager
    }

    var isReady: Bool {
        modelManager.isDownloaded
    }

    var isLoadingEngine: Bool {
        modelManager.isLoading
    }

    private let modelManager: PocketTTSModelManager

    init(modelManager: PocketTTSModelManager) {
        self.modelManager = modelManager
    }

    // MARK: - Voices

    /// Custom voice catalog — only bundled voices, not PocketTTS built-ins.
    private static let voiceCatalog: [(id: String, name: String)] = [
        // UK
        ("alice", "Alice (UK)"),
        ("arthur", "Arthur (UK)"),
        ("emma", "Emma (UK)"),
        ("harry", "Harry (UK)"),
        ("james", "James (UK)"),
        ("kate", "Kate (UK)"),
        // US
        ("amy", "Amy (US)"),
        ("ben", "Ben (US)"),
        ("jordan", "Jordan (US)"),
        ("max", "Max (US)"),
        ("sam", "Sam (US)"),
        ("taylor", "Taylor (US)"),
    ]

    func availableVoices(for language: AppLanguage) -> [SpeechVoice] {
        guard language == .english else { return [] }
        return Self.voiceCatalog.map { entry in
            SpeechVoice(
                engine: .pocketTTS,
                identifier: entry.id,
                displayName: entry.name,
                languageCode: "en-US",
                dialect: nil
            )
        }
    }

    func makeSynthesizer(voice: SpeechVoice?, language: AppLanguage) -> any SpeechSynthesizing {
        let voiceID = voice?.identifier ?? Self.voiceCatalog[0].id
        return PocketTTSSpeechSynthesizer(modelManager: modelManager, voiceName: voiceID)
    }
}

#endif
