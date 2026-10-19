#if !targetEnvironment(simulator)
import Foundation

/// Configuration constants for the Plapre Pico TTS pipeline.
///
/// Values are fixed by the model architecture and must match the converted CoreML models
/// in https://huggingface.co/42futures/plapre-pico-coreml. Ported from the upstream
/// `swift-cli/Sources/Configuration.swift`.
enum PlaprePicoConfig {
    // MARK: - Audio

    static let sampleRate: Double = 24000
    static let audioTokensPerSecond: Int = 25

    // MARK: - Model architecture

    static let vocabSize = 20802
    static let maxContextLength = 512
    static let prefillSequenceLength = 512
    static let hiddenDimension = 576
    static let headDimension = 64
    static let numKVHeads = 3
    static let speakerEmbeddingDimension = 128

    // MARK: - Token IDs

    static let eosToken: Int32 = 0
    static let textMarkerToken: Int32 = 8000
    static let audioMarkerToken: Int32 = 8001
    static let audioTokenOffset: Int32 = 8002
    static let audioTokenMax: Int32 = 20801

    // MARK: - Inference

    static let defaultTemperature: Float = 0.5
    static let defaultTopK = 40
    static let maxGenerationTokens = 500
    static let nonAudioStopThreshold = 10

    // MARK: - Vocoder

    /// 100 audio tokens = 4 seconds at 25 tok/s.
    static let kanadeChunkSize = 100

    // MARK: - Playback smoothing

    /// Linear crossfade length.
    /// Long enough to hide vocoder chunk-boundary discontinuities but short
    /// enough to be inaudible as a volume dip.
    static let crossfadeSamples = 128

    /// Short pause inserted between utterances. Applies at every sentence
    /// boundary (since the speech service chunks per sentence), so keep it
    /// well below a "paragraph break" feel — this is just enough to mask any
    /// residual chunk-boundary artefact and give natural breath at sentence
    /// transitions without feeling laggy.
    static let interUtteranceSilence: TimeInterval = 0.1

    // MARK: - Voices

    /// The five Danish speakers shipped in `speakers.json`.
    /// Ordered by preference: the first entry is the default.
    static let speakers = ["ida", "kaj", "liv", "tor", "ask"]
    static let defaultSpeaker = speakers[0]
}
#endif
