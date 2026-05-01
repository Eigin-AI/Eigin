#if !targetEnvironment(simulator)
import CoreML
import Foundation
import Tokenizers

/// Holds the loaded Plapre Pico model state for the lifetime of one
/// "in memory" interval. Equivalent to `PocketTtsManager`.
///
/// Owns the three CoreML models, the BPE tokenizer, the rope tables, and
/// the parsed speaker map. Vends `PlaprePicoSession`s.
final class PlaprePicoManager: @unchecked Sendable {
    let decodeModel: MLModel
    let kanadeModel: MLModel
    let vocoderModel: MLModel
    let tokenizer: any Tokenizer
    let ropeCos: [Float]
    let ropeSin: [Float]
    let speakers: [String: [Float]]

    private init(
        decodeModel: MLModel,
        kanadeModel: MLModel,
        vocoderModel: MLModel,
        tokenizer: any Tokenizer,
        ropeCos: [Float],
        ropeSin: [Float],
        speakers: [String: [Float]]
    ) {
        self.decodeModel = decodeModel
        self.kanadeModel = kanadeModel
        self.vocoderModel = vocoderModel
        self.tokenizer = tokenizer
        self.ropeCos = ropeCos
        self.ropeSin = ropeSin
        self.speakers = speakers
    }

    /// Loads everything from the on-disk cache (`PlaprePicoAssets.rootDirectory`).
    /// Heavy: compiles models, parses ~3 MB of tokenizer JSON, reads rope tables.
    static func load() async throws -> PlaprePicoManager {
        let root = PlaprePicoAssets.rootDirectory
        let config = MLModelConfiguration()
        // Neither the `_int8` nor the full-precision `PlaprePico` variant compiles
        // for ANE today (MIL→EIR std::bad_cast). The GPU path is slow for these
        // small autoregressive ops. CPU is the only working target — matches
        // upstream's default.
        config.computeUnits = .cpuOnly

        let decodeModel = try MLModel(
            contentsOf: PlaprePicoAssets.compiledModelURL("PlaprePico"),
            configuration: config
        )
        let kanadeModel = try MLModel(
            contentsOf: PlaprePicoAssets.compiledModelURL("KanadeDecoder"),
            configuration: config
        )
        let vocoderModel = try MLModel(
            contentsOf: PlaprePicoAssets.compiledModelURL("Vocoder"),
            configuration: config
        )
        let tokenizer = try await AutoTokenizer.from(modelFolder: root)
        let ropeCos = try PlaprePicoInference.loadRopeTable(
            at: PlaprePicoAssets.supportingFileURL("rope_cos.npy")
        )
        let ropeSin = try PlaprePicoInference.loadRopeTable(
            at: PlaprePicoAssets.supportingFileURL("rope_sin.npy")
        )
        let speakers = try PlaprePicoInference.loadSpeakers(
            at: PlaprePicoAssets.supportingFileURL("speakers.json")
        )

        AppLogger.info("Plapre: loaded", category: .general)

        return PlaprePicoManager(
            decodeModel: decodeModel,
            kanadeModel: kanadeModel,
            vocoderModel: vocoderModel,
            tokenizer: tokenizer,
            ropeCos: ropeCos,
            ropeSin: ropeSin,
            speakers: speakers
        )
    }

    /// Creates a new session for the given voice. Resolves the speaker embedding,
    /// allocates per-session scratch buffers, and starts the session generator loop.
    func makeSession(voice: String) throws -> PlaprePicoSession {
        let embedding = try PlaprePicoInference.speakerEmbedding(voice, in: speakers)
        let session = try PlaprePicoSession(manager: self, speakerEmbedding: embedding)
        session.start()
        return session
    }
}
#endif
