#if !targetEnvironment(simulator)
import CoreML
import Foundation

/// Pure inference primitives for the Plapre Pico pipeline. Stateless functions
/// over `MLModel` handles plus a small `DecodeScratch` struct of pre-allocated
/// `MLMultiArray`s reused across decode steps.
///
/// Direct port of the upstream `swift-cli/Sources/Inference.swift`,
/// `CoreMLUtils.swift`, and `DataLoading.swift`.
enum PlaprePicoInference {
    // MARK: - Errors

    enum InferenceError: Error, LocalizedError {
        case missingOutput(String)
        case invalidNpyHeader(String)
        case speakerNotFound(String, [String])
        case invalidSpeakersFile

        var errorDescription: String? {
            switch self {
            case .missingOutput(let name): "CoreML output '\(name)' not found"
            case .invalidNpyHeader(let path): "Invalid .npy header in \(path)"
            case .speakerNotFound(let name, let available):
                "Speaker '\(name)' not found. Available: \(available.sorted().joined(separator: ", "))"
            case .invalidSpeakersFile: "speakers.json is not in the expected format"
            }
        }
    }

    // MARK: - MLMultiArray helpers

    static func makeFloat16Array(_ values: [Float], shape: [Int]) -> MLMultiArray {
        let arr = try! MLMultiArray(shape: shape.map { NSNumber(value: $0) }, dataType: .float16)
        arr.withUnsafeMutableBufferPointer(ofType: Float16.self) { ptr, _ in
            for i in 0 ..< values.count {
                ptr[i] = Float16(values[i])
            }
        }
        return arr
    }

    static func makeFloat32Array(_ values: [Float], shape: [Int]) -> MLMultiArray {
        let arr = try! MLMultiArray(shape: shape.map { NSNumber(value: $0) }, dataType: .float32)
        arr.withUnsafeMutableBufferPointer(ofType: Float.self) { dst, _ in
            for i in 0 ..< values.count {
                dst[i] = values[i]
            }
        }
        return arr
    }

    static func makeInt32Array(_ values: [Int32], shape: [Int]) -> MLMultiArray {
        let arr = try! MLMultiArray(shape: shape.map { NSNumber(value: $0) }, dataType: .int32)
        arr.withUnsafeMutableBufferPointer(ofType: Int32.self) { dst, _ in
            for i in 0 ..< values.count {
                dst[i] = values[i]
            }
        }
        return arr
    }

    static func readFloat32Array(_ array: MLMultiArray) -> [Float] {
        let count = array.count
        var result = [Float](repeating: 0, count: count)
        array.withUnsafeBufferPointer(ofType: Float.self) { ptr in
            for i in 0 ..< count {
                result[i] = ptr[i]
            }
        }
        return result
    }

    // MARK: - Asset loaders

    /// Loads a `.npy` file containing Float16 values, returning Float32 values.
    /// Implements only the subset of the .npy format produced by numpy for
    /// little-endian 1-D Float16 arrays — sufficient for the rope tables.
    static func loadRopeTable(at url: URL) throws -> [Float] {
        let data = try Data(contentsOf: url)
        var headerEnd = 0
        for i in 0 ..< data.count where data[i] == 0x0A {
            if i > 5 {
                let candidate = i + 1
                if (data.count - candidate) % 2 == 0 {
                    headerEnd = candidate
                    break
                }
            }
        }
        guard headerEnd > 0 else {
            throw InferenceError.invalidNpyHeader(url.lastPathComponent)
        }
        let raw = data.subdata(in: headerEnd ..< data.count)
        let count = raw.count / 2
        var result = [Float](repeating: 0, count: count)
        raw.withUnsafeBytes { ptr in
            let f16 = ptr.bindMemory(to: Float16.self)
            for i in 0 ..< count {
                result[i] = Float(f16[i])
            }
        }
        return result
    }

    /// Parses speakers.json into a `[name: embedding]` map.
    static func loadSpeakers(at url: URL) throws -> [String: [Float]] {
        let data = try Data(contentsOf: url)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: [Double]] else {
            throw InferenceError.invalidSpeakersFile
        }
        return json.mapValues { $0.map { Float($0) } }
    }

    static func speakerEmbedding(_ name: String, in map: [String: [Float]]) throws -> [Float] {
        guard let emb = map[name] else {
            throw InferenceError.speakerNotFound(name, Array(map.keys))
        }
        return emb
    }

    // MARK: - Sampling

    static func sampleFromLogits(
        _ logits: [Float16],
        temperature: Float = PlaprePicoConfig.defaultTemperature,
        topK: Int = PlaprePicoConfig.defaultTopK
    ) -> Int32 {
        logits.withUnsafeBufferPointer { ptr -> Int32 in
            var topIndices = [Int](repeating: 0, count: topK)
            var topValues = [Float16](repeating: Float16(-65504), count: topK)
            var minIdx = 0

            for i in 0 ..< PlaprePicoConfig.vocabSize {
                if ptr[i] > topValues[minIdx] {
                    topValues[minIdx] = ptr[i]
                    topIndices[minIdx] = i
                    minIdx = 0
                    for j in 1 ..< topK where topValues[j] < topValues[minIdx] {
                        minIdx = j
                    }
                }
            }

            if temperature <= 0 {
                var bestIdx = 0
                for j in 1 ..< topK where topValues[j] > topValues[bestIdx] {
                    bestIdx = j
                }
                return Int32(topIndices[bestIdx])
            }

            var logits32 = [Float](repeating: 0, count: topK)
            for j in 0 ..< topK {
                logits32[j] = Float(topValues[j]) / temperature
            }
            let maxVal = logits32.max()!
            var exps = logits32.map { exp($0 - maxVal) }
            let sum = exps.reduce(0, +)
            for j in 0 ..< topK {
                exps[j] /= sum
            }

            let r = Float.random(in: 0 ..< 1)
            var cumsum: Float = 0
            for j in 0 ..< topK {
                cumsum += exps[j]
                if cumsum >= r { return Int32(topIndices[j]) }
            }
            return Int32(topIndices[topK - 1])
        }
    }

    // MARK: - Decode scratch buffers

    /// Custom feature provider that returns a **fresh** `MLFeatureValue` on every
    /// access. Upstream's note: "Critical for performance: prevents CoreML from
    /// caching stale array data." Using `MLDictionaryFeatureProvider` instead
    /// roughly halves throughput on CPU.
    final class DecodeInputProvider: NSObject, MLFeatureProvider {
        let featureNames: Set<String> = [
            "input_ids", "causal_mask", "cos", "sin",
            "update_mask", "speaker_embedding", "is_speaker_step",
        ]
        private let arrays: [String: MLMultiArray]

        init(_ arrays: [String: MLMultiArray]) {
            self.arrays = arrays
        }

        func featureValue(for featureName: String) -> MLFeatureValue? {
            guard let arr = arrays[featureName] else { return nil }
            return MLFeatureValue(multiArray: arr)
        }
    }

    /// Pre-allocated `MLMultiArray`s reused across decode steps to avoid allocator churn.
    /// One instance per session — sized once at session creation.
    final class DecodeScratch {
        let inputIds: MLMultiArray
        let causalMask: MLMultiArray
        let cos: MLMultiArray
        let sin: MLMultiArray
        let updateMask: MLMultiArray
        let speakerEmbedding: MLMultiArray // float16, set once per session
        let isSpeakerStep: MLMultiArray
        let provider: DecodeInputProvider
        /// Reusable logits buffer written into on every decode step.
        var logits: [Float16]

        init(speakerEmbedding speakerEmb: [Float]) throws {
            inputIds = try MLMultiArray(shape: [1, 1], dataType: .int32)
            causalMask = try MLMultiArray(
                shape: [1, 1, 1, NSNumber(value: PlaprePicoConfig.maxContextLength)],
                dataType: .float16
            )
            cos = try MLMultiArray(
                shape: [1, 1, 1, NSNumber(value: PlaprePicoConfig.headDimension)],
                dataType: .float16
            )
            sin = try MLMultiArray(
                shape: [1, 1, 1, NSNumber(value: PlaprePicoConfig.headDimension)],
                dataType: .float16
            )
            updateMask = try MLMultiArray(
                shape: [1, 1, NSNumber(value: PlaprePicoConfig.maxContextLength), 1],
                dataType: .float16
            )
            speakerEmbedding = PlaprePicoInference.makeFloat16Array(
                speakerEmb,
                shape: [1, PlaprePicoConfig.speakerEmbeddingDimension]
            )
            isSpeakerStep = try MLMultiArray(shape: [1], dataType: .float16)
            logits = [Float16](repeating: 0, count: PlaprePicoConfig.vocabSize)

            provider = DecodeInputProvider([
                "input_ids": inputIds,
                "causal_mask": causalMask,
                "cos": cos,
                "sin": sin,
                "update_mask": updateMask,
                "speaker_embedding": speakerEmbedding,
                "is_speaker_step": isSpeakerStep,
            ])
        }

        /// Resets the causal mask and update mask for a fresh utterance.
        func resetMasks() {
            causalMask.withUnsafeMutableBufferPointer(ofType: Float16.self) { ptr, _ in
                for i in 0 ..< PlaprePicoConfig.maxContextLength {
                    ptr[i] = Float16(-65504)
                }
            }
            updateMask.withUnsafeMutableBufferPointer(ofType: Float16.self) { ptr, _ in
                for i in 0 ..< PlaprePicoConfig.maxContextLength {
                    ptr[i] = Float16(0)
                }
            }
        }
    }

    // MARK: - Decode step

    /// Runs a single autoregressive decode step. Mutates `scratch.logits` in place
    /// with the result; use `scratch.logits` to sample after the call.
    static func runDecodeStep(
        model: MLModel,
        state: MLState,
        scratch: DecodeScratch,
        ropeCos: [Float],
        ropeSin: [Float],
        token: Int32,
        pos: Int,
        isSpeaker: Bool
    ) throws {
        scratch.inputIds.withUnsafeMutableBufferPointer(ofType: Int32.self) { ptr, _ in
            ptr[0] = token
        }
        scratch.causalMask.withUnsafeMutableBufferPointer(ofType: Float16.self) { ptr, _ in
            ptr[pos] = Float16(0)
        }
        let ropeOffset = pos * PlaprePicoConfig.headDimension
        scratch.cos.withUnsafeMutableBufferPointer(ofType: Float16.self) { ptr, _ in
            for i in 0 ..< PlaprePicoConfig.headDimension {
                ptr[i] = Float16(ropeCos[ropeOffset + i])
            }
        }
        scratch.sin.withUnsafeMutableBufferPointer(ofType: Float16.self) { ptr, _ in
            for i in 0 ..< PlaprePicoConfig.headDimension {
                ptr[i] = Float16(ropeSin[ropeOffset + i])
            }
        }
        scratch.updateMask.withUnsafeMutableBufferPointer(ofType: Float16.self) { ptr, _ in
            if pos > 0 { ptr[pos - 1] = Float16(0) }
            ptr[pos] = Float16(1)
        }
        scratch.isSpeakerStep.withUnsafeMutableBufferPointer(ofType: Float16.self) { ptr, _ in
            ptr[0] = isSpeaker ? Float16(1) : Float16(0)
        }

        let output = try model.prediction(from: scratch.provider, using: state)
        guard let arr = output.featureValue(for: "logits")?.multiArrayValue else {
            throw InferenceError.missingOutput("logits")
        }
        arr.withUnsafeBufferPointer(ofType: Float16.self) { ptr in
            scratch.logits.withUnsafeMutableBufferPointer { dst in
                for i in 0 ..< PlaprePicoConfig.vocabSize {
                    dst[i] = ptr[i]
                }
            }
        }
    }

    // MARK: - Kanade + Vocoder

    /// Runs a single chunk through KanadeDecoder + Vocoder, returning the *unpadded*
    /// audio samples for the actual (pre-padding) token count.
    static func runAudioChunk(
        kanade: MLModel,
        vocoder: MLModel,
        audioTokens: ArraySlice<Int32>,
        speakerEmbeddingF32: MLMultiArray
    ) throws -> [Float] {
        let actualCount = audioTokens.count
        var indices = audioTokens.map { $0 - PlaprePicoConfig.audioTokenOffset }
        let pad = indices.last ?? 0
        while indices.count < PlaprePicoConfig.kanadeChunkSize {
            indices.append(pad)
        }

        let kanadeInput = try MLDictionaryFeatureProvider(dictionary: [
            "token_indices": MLFeatureValue(
                multiArray: makeInt32Array(indices, shape: [PlaprePicoConfig.kanadeChunkSize])
            ),
            "speaker_embedding": MLFeatureValue(multiArray: speakerEmbeddingF32),
        ])
        let kanadeOutput = try kanade.prediction(from: kanadeInput)
        guard let mel = kanadeOutput.featureValue(for: "mel")?.multiArrayValue else {
            throw InferenceError.missingOutput("mel")
        }

        let vocoderInput = try MLDictionaryFeatureProvider(dictionary: [
            "mel": MLFeatureValue(multiArray: mel),
        ])
        let vocoderOutput = try vocoder.prediction(from: vocoderInput)
        guard let waveformArr = vocoderOutput.featureValue(for: "waveform")?.multiArrayValue else {
            throw InferenceError.missingOutput("waveform")
        }
        let waveform = readFloat32Array(waveformArr)
        let samplesPerToken = waveform.count / PlaprePicoConfig.kanadeChunkSize
        let usable = actualCount * samplesPerToken
        return Array(waveform.prefix(usable))
    }
}
#endif
