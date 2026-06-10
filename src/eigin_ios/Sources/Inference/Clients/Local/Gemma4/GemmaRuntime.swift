@preconcurrency import CoreML
import Foundation
import Tokenizers

/// On-device LLM inference using CoreML with ANE optimization.
///
/// Supports both monolithic models (single .mlpackage) and chunked SWA models
/// (Gemma 4 E2B with 4 decode + 4 prefill chunks + external embeddings).
///
/// ```swift
/// let llm = try await GemmaRuntime.load(from: modelDirectory)
///
/// // Simple single-turn
/// let answer = try await llm.generate("What is the capital of France?")
///
/// // Streaming
/// for await token in try await llm.stream("Tell me a story") {
///     print(token, terminator: "")
/// }
///
/// // Multi-turn conversation
/// let messages: [GemmaRuntime.Message] = [
///     .init(role: .user, content: "Hi!"),
///     .init(role: .assistant, content: "Hello!"),
///     .init(role: .user, content: "What is 2+2?"),
/// ]
/// for await token in try await llm.stream(messages) {
///     print(token, terminator: "")
/// }
/// ```
public final class GemmaRuntime: @unchecked Sendable {
    private let tokenizer: any Tokenizer
    private var config: GemmaModelConfig

    // Engine: exactly one of these is non-nil.
    private var chunkedEngine: ChunkedEngine?
    private var monolithicModel: MLModel?
    private var monolithicState: MLState?

    // Token buffers for bench helpers
    private var lastPromptTokenIDs: [Int32] = []
    private var lastEmittedTokenIDs: [Int32] = []

    /// MTP speculative decoding
    private var mtpEngine: MtpSpeculativeEngine?
    /// Toggle MTP speculation on/off for benchmarking.
    public var mtpEnabled: Bool = true

    // Generation metrics
    public private(set) var tokensPerSecond: Double = 0
    public var mtpAcceptanceRate: Double {
        mtpEngine?.acceptanceRate ?? 0
    }

    public var mtpTokensPerRound: Double {
        mtpEngine?.tokensPerRound ?? 0
    }

    /// Expose the tokenizer so a harness can re-encode / decode arbitrary
    /// text without duplicating the swift-transformers wiring.
    public var tokenizerRef: any Tokenizer {
        tokenizer
    }

    // MARK: - Public Types

    /// A message in a multi-turn conversation.
    public struct Message: Sendable {
        public enum Role: String, Sendable {
            case user, assistant, system
        }

        public let role: Role
        public let content: String

        public init(role: Role, content: String) {
            self.role = role
            self.content = content
        }
    }

    private init(config: GemmaModelConfig, tokenizer: any Tokenizer) {
        self.config = config
        self.tokenizer = tokenizer
    }

    // MARK: - Public API

    /// Load a model from a local directory.
    ///
    /// Auto-detects layout:
    /// - If `chunk1.mlmodelc` exists → chunked SWA engine (Gemma 4 E2B)
    /// - Otherwise → monolithic model (`model.mlpackage` / `model.mlmodelc`)
    ///
    /// - Parameters:
    ///   - directory: Folder containing model files, embeddings, config
    ///   - computeUnits: CoreML compute units (default: `.cpuAndNeuralEngine`)
    ///   - onProgress: Optional callback for loading status updates
    public static func load(
        from directory: URL,
        computeUnits: MLComputeUnits = .cpuAndNeuralEngine,
        onProgress: ((String) -> Void)? = nil,
        onChunkLoaded: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> GemmaRuntime {
        onProgress?("Reading config...")
        let config = try GemmaModelConfig.load(from: directory)

        // Tokenizer
        onProgress?("Loading tokenizer...")
        let tokDir = directory.appendingPathComponent("hf_model")
        let tokenizer = try await AutoTokenizer.from(modelFolder: tokDir)

        let llm = GemmaRuntime(config: config, tokenizer: tokenizer)

        // Auto-detect: chunked or monolithic
        let isChunked = FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("chunk1.mlmodelc").path
        )
            || FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("chunk1.mlpackage").path
            )

        if isChunked {
            onProgress?("Loading chunks (first run = ANE compile, can take 1-2 min)...")
            llm.chunkedEngine = try await ChunkedEngine.load(
                from: directory, config: config, computeUnits: computeUnits,
                onChunkLoaded: onChunkLoaded
            )
        } else {
            let mlConfig = MLModelConfiguration()
            mlConfig.computeUnits = computeUnits
            let modelURL = directory.appendingPathComponent("model.mlmodelc")
            if FileManager.default.fileExists(atPath: modelURL.path) {
                onProgress?("Loading model...")
                llm.monolithicModel = try MLModel(contentsOf: modelURL, configuration: mlConfig)
            } else {
                onProgress?("Compiling model...")
                let pkgURL = directory.appendingPathComponent("model.mlpackage")
                let compiled = try await MLModel.compileModel(at: pkgURL)
                llm.monolithicModel = try MLModel(contentsOf: compiled, configuration: mlConfig)
            }
            llm.monolithicState = llm.monolithicModel?.makeState()
        }

        // MTP drafter (optional — enables speculative decoding)
        let mtpCompiled = directory.appendingPathComponent("mtp_drafter.mlmodelc")
        let mtpPkg = directory.appendingPathComponent("mtp_drafter.mlpackage")
        let mtpURL: URL? = FileManager.default.fileExists(atPath: mtpCompiled.path) ? mtpCompiled
            : FileManager.default.fileExists(atPath: mtpPkg.path) ? mtpPkg : nil
        if let mtpURL, let engine = llm.chunkedEngine, engine.hasVerify {
            onProgress?("Loading MTP drafter...")
            do {
                let drafterSource = try MtpDraftSource(
                    modelURL: mtpURL, K: engine.verifyK
                )
                llm.mtpEngine = MtpSpeculativeEngine(
                    engine: engine, drafter: drafterSource
                )
                AppLogger.info(
                    "Gemma: MTP drafter loaded (K=\(public: engine.verifyK))",
                    category: .chat
                )
            } catch {
                AppLogger.warning(
                    "Gemma: MTP drafter failed to load: \(public: error.localizedDescription)",
                    category: .chat
                )
            }
        }

        onProgress?("Ready")
        return llm
    }

    /// Download (if needed) and load a model in one call.
    ///
    /// ```swift
    /// let llm = try await LocalLLM.load(model: .gemma4e2b) { print($0) }
    /// ```
    ///
    /// If the model is already downloaded, skips straight to loading.
    public static func load(
        model: GemmaModelDownloader.ModelInfo,
        computeUnits: MLComputeUnits = .cpuAndNeuralEngine,
        onProgress: ((String) -> Void)? = nil,
        onChunkLoaded: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> GemmaRuntime {
        let downloader = GemmaModelDownloader.shared
        let modelURL: URL
        if let existing = downloader.localModelURL(for: model) {
            modelURL = existing
        } else {
            onProgress?("Downloading \(model.name)...")
            modelURL = try await downloader.download(model)
        }
        let directory = modelURL.deletingLastPathComponent()
        return try await load(
            from: directory,
            computeUnits: computeUnits,
            onProgress: onProgress,
            onChunkLoaded: onChunkLoaded
        )
    }

    /// Model name from config.
    public var modelName: String {
        config.modelName
    }

    /// Context length from config.
    public var contextLength: Int {
        config.contextLength
    }

    // MARK: - Single-turn convenience

    /// Generate a complete response from a single prompt.
    public func generate(
        _ prompt: String,
        maxTokens: Int = 2048
    ) async throws -> String {
        let messages = [Message(role: .user, content: prompt)]
        return try await generate(messages, maxTokens: maxTokens)
    }

    /// Stream tokens from a single prompt.
    public func stream(
        _ prompt: String,
        maxTokens: Int = 2048
    ) async throws -> AsyncStream<String> {
        let messages = [Message(role: .user, content: prompt)]
        return try await stream(messages, maxTokens: maxTokens)
    }

    // MARK: - Multi-turn API

    /// Generate a complete response from a conversation.
    public func generate(
        _ messages: [Message],
        maxTokens: Int = 2048
    ) async throws -> String {
        var result = ""
        for await token in try await stream(
            messages,
            maxTokens: maxTokens
        ) {
            result += token
        }
        return result
    }

    /// Stream tokens from a multi-turn conversation.
    public func stream(
        _ messages: [Message],
        maxTokens: Int = 2048
    ) async throws -> AsyncStream<String> {
        let tokenIDs: [Int]
        do {
            let templateMessages: [[String: any Sendable]] = messages.map { m in
                ["role": m.role.rawValue, "content": m.content]
            }
            tokenIDs = try tokenizer.applyChatTemplate(
                messages: templateMessages,
                chatTemplate: GemmaChatTemplate.jinja
            )
        } catch {
            AppLogger.warning(
                "GemmaRuntime: applyChatTemplate failed (\(public: error.localizedDescription)), falling back to manual buildPrompt",
                category: .chat
            )
            let chatPrompt = buildPrompt(messages)
            tokenIDs = tokenizer.encode(text: chatPrompt)
        }

        if tokenIDs.count < 3 {
            AppLogger.error(
                "GemmaRuntime: tokenIDs too short (\(public: tokenIDs.count)), prompt may be malformed. First few: \(public: tokenIDs.prefix(10))",
                category: .chat
            )
        }

        reset()

        // Clear recording buffers and record the prompt IDs for this turn.
        lastPromptTokenIDs = tokenIDs.map { Int32($0) }
        lastEmittedTokenIDs = []

        let mutableSelf = self
        let tokens = tokenIDs
        let ctxLimit = config.contextLength

        let (stream, continuation) = AsyncStream<String>.makeStream()
        Task {
            do {
                var nextID = 0

                let engine = mutableSelf.chunkedEngine

                if let engine {
                    let prefillLen = min(tokens.count, engine.prefillN)
                    let useHybrid = engine.hasPrefill && prefillLen > 0

                    if useHybrid {
                        try autoreleasepool {
                            let batch = Array(tokens[0 ..< prefillLen])
                            nextID = try engine.runPrefill(tokenIDs: batch)
                        }
                        engine.currentPosition = prefillLen

                        for step in prefillLen ..< tokens.count {
                            try autoreleasepool {
                                nextID = try engine.predictStep(
                                    tokenID: tokens[step],
                                    position: step
                                )
                            }
                            engine.currentPosition = step + 1
                        }
                    } else {
                        for (step, tid) in tokens.enumerated() {
                            try autoreleasepool {
                                nextID = try engine.predictStep(tokenID: tid, position: step)
                            }
                            engine.currentPosition = step + 1
                        }
                    }

                    // Decode loop with tok/s tracking
                    let eosIDs: Set = [1, 106, 151_645]
                    let startTime = CFAbsoluteTimeGetCurrent()
                    var tokenCount = 0
                    var consecutivePads = 0
                    let maxDecode = min(ctxLimit - engine.currentPosition, maxTokens)
                    let mtpSpec = mutableSelf.mtpEnabled ? mutableSelf.mtpEngine : nil
                    mtpSpec?.reset()

                    var nid = Int32(nextID)
                    while tokenCount < maxDecode {
                        if eosIDs.contains(Int(nid)) { break }
                        if engine.currentPosition >= ctxLimit { break }
                        // Safety: stop if we get too many consecutive pad tokens
                        if nid == 0 {
                            consecutivePads += 1
                            if consecutivePads > 10 { break }
                        } else {
                            consecutivePads = 0
                        }

                        if let se = mtpSpec, se.shouldSpeculate {
                            let emitted = try autoreleasepool {
                                try se.speculateStep(nextID: &nid)
                            }
                            for tok in emitted {
                                if eosIDs.contains(Int(tok)) {
                                    nid = tok
                                    break
                                }
                                let text = mutableSelf.tokenizer.decode(tokens: [Int(tok)])
                                continuation.yield(text)
                                tokenCount += 1
                            }
                        } else {
                            mutableSelf.lastEmittedTokenIDs.append(nid)
                            let text = mutableSelf.tokenizer.decode(tokens: [Int(nid)])
                            continuation.yield(text)
                            tokenCount += 1
                            try autoreleasepool {
                                let next = try engine.predictStep(
                                    tokenID: Int(nid), position: engine.currentPosition
                                )
                                nid = Int32(next)
                            }
                            engine.currentPosition += 1
                        }

                        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
                        if elapsed >
                            0 { mutableSelf.tokensPerSecond = Double(tokenCount) / elapsed }
                    }
                    nextID = Int(nid)
                } else {
                    // Monolithic path
                    for (step, tid) in tokens.enumerated() {
                        try autoreleasepool {
                            nextID = try mutableSelf.predictMonolithic(
                                tokenID: tid, position: step
                            )
                        }
                    }
                    let eosIDs: Set = [1, 106, 151_645]
                    let startTime = CFAbsoluteTimeGetCurrent()
                    var pos = tokens.count
                    var tokenCount = 0
                    for _ in 0 ..< maxTokens {
                        if eosIDs.contains(nextID) { break }
                        if pos >= ctxLimit { break }
                        mutableSelf.lastEmittedTokenIDs.append(Int32(nextID))
                        let text = mutableSelf.tokenizer.decode(tokens: [nextID])
                        continuation.yield(text)
                        tokenCount += 1
                        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
                        if elapsed >
                            0 { mutableSelf.tokensPerSecond = Double(tokenCount) / elapsed }
                        try autoreleasepool {
                            nextID = try mutableSelf.predictMonolithic(
                                tokenID: nextID, position: pos
                            )
                        }
                        pos += 1
                    }
                }
            } catch {
                AppLogger.error(
                    "Gemma: generation error: \(private: error.localizedDescription)",
                    category: .chat
                )
            }
            continuation.finish()
        }
        return stream
    }

    /// Reset conversation state (clears KV cache).
    public func reset() {
        if let engine = chunkedEngine {
            engine.reset()
        } else {
            monolithicState = monolithicModel?.makeState()
        }
        mtpEngine?.reset()
        tokensPerSecond = 0
    }

    // MARK: - Bench helpers (offline harness use only; not for production)

    /// Chunked-engine verify K (typically 3). Nil if the monolithic path is
    /// in use or verify chunks aren't loaded.
    public var benchVerifyK: Int? {
        guard let e = chunkedEngine, e.hasVerify else { return nil }
        return e.verifyK
    }

    /// Current decode position on the chunked engine, or nil on monolithic.
    public var benchCurrentPosition: Int? {
        chunkedEngine?.currentPosition
    }

    /// Run prefill + sequential `predictStep` for any tokens that didn't fit
    /// in a prefill chunk. After return, `benchCurrentPosition ==
    /// promptTokens.count` and `seed` is target's argmax (via `decode_q1`) for
    /// that position — the token to emit first. Resets engine + spec engines.
    ///
    /// Text prompts only; image/audio paths are not handled.
    public func benchPrefill(_ prompt: String) async throws -> (prompt: [Int32], seed: Int32) {
        guard let engine = chunkedEngine else {
            throw GemmaRuntimeError.predictionFailed
        }
        let messages = [Message(role: .user, content: prompt)]
        let chatPrompt = buildPrompt(messages)
        let tokens = tokenizer.encode(text: chatPrompt)
        reset()
        lastPromptTokenIDs = tokens.map { Int32($0) }
        lastEmittedTokenIDs = []

        var nextID = 0
        let prefillLen = min(tokens.count, engine.prefillN)
        let useHybrid = engine.hasPrefill && prefillLen > 0
        if useHybrid {
            try autoreleasepool {
                let batch = Array(tokens[0 ..< prefillLen])
                nextID = try engine.runPrefill(tokenIDs: batch)
            }
            engine.currentPosition = prefillLen
            for step in prefillLen ..< tokens.count {
                try autoreleasepool {
                    nextID = try engine.predictStep(tokenID: tokens[step], position: step)
                }
                engine.currentPosition = step + 1
            }
        } else {
            for (step, tid) in tokens.enumerated() {
                try autoreleasepool {
                    nextID = try engine.predictStep(tokenID: tid, position: step)
                }
                engine.currentPosition = step + 1
            }
        }
        return (tokens.map { Int32($0) }, Int32(nextID))
    }

    /// Run `verify_qK` at the current decode position. `tokens.count` must
    /// equal `benchVerifyK`. Returns target's argmax at each of K positions.
    /// Writes K KV slots starting at `benchCurrentPosition` but does NOT
    /// advance the position — use `benchAdvance(by:)` to commit.
    public func benchVerify(_ tokens: [Int32]) throws -> [Int32] {
        guard let engine = chunkedEngine, engine.hasVerify else {
            throw GemmaRuntimeError.predictionFailed
        }
        return try engine.verifyCandidates(
            tokens: tokens,
            startPosition: engine.currentPosition
        )
    }

    /// Variant of `benchVerify` that also returns per-position top-`topK`
    /// `(token_id, logit_fp32)` pairs. Used by the tolerance-based accept
    /// variant of `accept-rate-bench`.
    ///
    /// Throws `GemmaRuntimeError.verifyLogitsNotExposed` until the Track B
    /// (`feat/c0-verify-requant`) re-export of verify chunk 4 adds a
    /// `logits_fp16` output. Until that PR merges, callers must fall back to
    /// argmax-only acceptance via `benchVerify`.
    public func benchVerifyTopK(_ tokens: [Int32], topK: Int = 3) throws
        -> [[(Int32, Float)]]
    {
        guard let engine = chunkedEngine, engine.hasVerify else {
            throw GemmaRuntimeError.predictionFailed
        }
        let (_, top) = try engine.verifyCandidatesWithLogits(
            tokens: tokens,
            startPosition: engine.currentPosition,
            topK: topK
        )
        return top
    }

    /// Advance `benchCurrentPosition` by `count`.
    public func benchAdvance(by count: Int) {
        chunkedEngine?.currentPosition += count
    }

    // MARK: - Private: monolithic prediction

    private func predictMonolithic(
        tokenID: Int,
        position: Int,
        imageEmbedding: MLMultiArray? = nil
    ) throws -> Int {
        guard let model = monolithicModel, let state = monolithicState else {
            throw GemmaRuntimeError.predictionFailed
        }
        let ctx = config.contextLength
        let hs = config.hiddenSize

        let ids = try MLMultiArray(shape: [1, 1], dataType: .int32)
        ids[[0, 0] as [NSNumber]] = NSNumber(value: Int32(tokenID))
        let pos = try MLMultiArray(shape: [1], dataType: .int32)
        pos[0] = NSNumber(value: Int32(position))
        let mask = try MLMultiArray(shape: [1, 1, 1, NSNumber(value: ctx)], dataType: .float16)
        let mp = mask.dataPointer.bindMemory(to: UInt16.self, capacity: ctx)
        for i in 0 ..< ctx {
            mp[i] = i <= position ? 0 : 0xFC00
        }
        let umask = try MLMultiArray(shape: [1, 1, NSNumber(value: ctx), 1], dataType: .float16)
        let up = umask.dataPointer.bindMemory(to: UInt16.self, capacity: ctx)
        memset(up, 0, ctx * MemoryLayout<UInt16>.stride)
        up[min(position, ctx - 1)] = 0x3C00

        var dict: [String: MLFeatureValue] = [
            "input_ids": MLFeatureValue(multiArray: ids),
            "position_ids": MLFeatureValue(multiArray: pos),
            "causal_mask": MLFeatureValue(multiArray: mask),
            "update_mask": MLFeatureValue(multiArray: umask),
        ]

        let inputNames = model.modelDescription.inputDescriptionsByName
        if inputNames["per_layer_combined"] != nil, let engine = chunkedEngine {
            let emb = try engine.computePerLayerCombined(
                tokenID: tokenID,
                embedding: MLMultiArray(
                    shape: [1, 1, NSNumber(value: hs)],
                    dataType: .float16
                )
            )
            dict["per_layer_combined"] = MLFeatureValue(multiArray: emb)
        }
        if inputNames["image_embedding"] != nil {
            let imgEmb: MLMultiArray
            if let imageEmbedding { imgEmb = imageEmbedding }
            else {
                imgEmb = try MLMultiArray(shape: [1, 1, NSNumber(value: hs)], dataType: .float16)
                memset(imgEmb.dataPointer, 0, hs * MemoryLayout<UInt16>.stride)
            }
            dict["image_embedding"] = MLFeatureValue(multiArray: imgEmb)
        }

        let output = try model.prediction(
            from: MLDictionaryFeatureProvider(dictionary: dict),
            using: state
        )
        return output.featureValue(for: "token_id")!.multiArrayValue![0].intValue
    }

    // MARK: - Private: prompt building

    private func buildPrompt(_ messages: [Message]) -> String {
        buildGemmaPrompt(messages)
    }

    private func buildGemmaPrompt(_ messages: [Message]) -> String {
        var p = "<bos>"
        for m in messages {
            switch m.role {
            case .system:
                p += "<|turn>system\n\(m.content)<turn|>\n"
            case .user:
                p += "<|turn>user\n\(m.content)<turn|>\n"
            case .assistant:
                p += "<|turn>model\n\(m.content)<turn|>\n"
            }
        }
        return p + "<|turn>model\n"
    }
}

// MARK: - ANE prewarm

extension GemmaRuntime {
    /// Touch every `.mlmodelc` bundle once to populate CoreML's ANE
    /// specialisation cache, then release each model immediately.
    ///
    /// This is the low-memory alternative to a full `load()`: it pays the
    /// minutes-long first-run specialisation cost without keeping the ~4 GB
    /// model resident. Subsequent `load()` calls against a warm cache complete
    /// in seconds rather than minutes.
    ///
    /// The cache is keyed on each bundle's absolute path + file metadata +
    /// `MLModelConfiguration` + OS build, so specialisation must be repeated
    /// after app updates (container UUID path changes), OS updates, and
    /// storage-pressure evictions. Call this once per app version via
    /// `GemmaModelManager.prewarmIfNeeded()`.
    ///
    /// - Parameters:
    ///   - directory: Root model directory (same as passed to `load(from:)`).
    ///   - computeUnits: Must match what `load()` uses so the cache hits.
    ///   - onProgress: Called with `(done, total)` after each entry is loaded.
    ///     Suitable for driving a progress indicator.
    static func prewarm(
        from directory: URL,
        computeUnits: MLComputeUnits = .cpuAndNeuralEngine,
        onProgress: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws {
        let entries = GemmaModelLayout.entries(in: directory, computeUnits: computeUnits)
        let total = entries.count
        for (index, entry) in entries.enumerated() {
            try Task.checkCancellation()
            let start = ContinuousClock.now
            // Load and immediately discard — we only want the e5rt cache populated.
            _ = try autoreleasepool {
                try MLModel(contentsOf: entry.url, configuration: entry.configuration)
            }
            let elapsed = start.duration(to: .now)
            let ms = elapsed.components.seconds * 1000
                + Int64(elapsed.components.attoseconds / 1_000_000_000_000_000)
            AppLogger.info(
                "GemmaRuntime: prewarm \(public: entry.name) in \(public: ms)ms",
                category: .chat
            )
            onProgress?(index + 1, total)
        }
    }
}

// MARK: - Error types

public enum GemmaRuntimeError: LocalizedError {
    case configNotFound
    case predictionFailed
    case modelNotFound(String)
    case prefillNotAvailable
    /// The verify-chunk pipeline does not expose a `logits_fp16` output yet.
    /// Returned by `benchVerifyTopK` / `verifyCandidatesWithLogits` until the
    /// Track B re-export (`feat/c0-verify-requant`) lands on `main`.
    case verifyLogitsNotExposed

    public var errorDescription: String? {
        switch self {
        case .configNotFound: "model_config.json not found"
        case .predictionFailed: "Model prediction failed"
        case .modelNotFound(let name): "Model file not found: \(name)"
        case .prefillNotAvailable: "Prefill chunks not loaded"
        case .verifyLogitsNotExposed:
            "verify chunk 4 does not expose `logits_fp16` (Track B re-export pending)"
        }
    }
}
