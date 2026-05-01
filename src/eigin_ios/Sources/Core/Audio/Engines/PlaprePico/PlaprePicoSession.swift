#if !targetEnvironment(simulator)
import CoreML
import Foundation
import Tokenizers

/// One audio chunk yielded from a `PlaprePicoSession`.
///
/// Mirrors the shape of `PocketTtsSynthesizer.AudioFrame` consumed by
/// the synthesizer layer.
struct PlaprePicoAudioFrame {
    /// Raw 24 kHz mono Float samples (one Kanade chunk's worth, unpadded).
    let samples: [Float]
    /// Index of the utterance this frame belongs to.
    let utteranceIndex: Int?
}

/// A chunk of audio tokens ready for Kanade+Vocoder synthesis.
private struct ChunkJob {
    let tokens: [Int32]
    let utteranceIndex: Int
}

/// Streams audio frames for a sequence of enqueued utterances. Equivalent to
/// `PocketTtsSession`. Run order:
///
/// 1. `makeSession(voice:)` constructs the session and calls `start()` once.
/// 2. Caller subscribes to `frames` (an `AsyncThrowingStream`) and calls
///    `enqueue(_:)` to push texts.
/// 3. `finish()` closes the input stream so the generator drains and exits.
/// 4. `cancel()` interrupts mid-utterance and `await`s the generator tasks.
///
/// ### Pipeline
///
/// Two concurrent tasks:
/// - **Decoder task** runs the autoregressive decode loop. Whenever a
///   `kanadeChunkSize` batch of audio tokens is ready, it pushes a `ChunkJob`
///   onto an internal chunk stream and *immediately continues decoding*. This
///   means the decode loop runs at close to its raw CoreML throughput (~26 tok/s
///   on CPU) instead of stalling on Kanade/Vocoder every 100 tokens.
/// - **Audio task** drains the chunk stream, runs Kanade → Vocoder on each
///   batch, and yields the resulting `AudioFrame`s to the public `frames`
///   stream.
///
/// Decoupling is the single biggest perf win available on CPU — it nearly
/// eliminates the Kanade/Vocoder stall that was dropping effective decode rate
/// from ~26 → ~16 tok/s.
///
/// State persisted **across** utterances within a session: the speaker
/// embedding, the pre-allocated decode scratch buffers, and the utterance
/// index counter. State **reset per utterance**: the CoreML decoder state
/// (`decodeModel.makeState()`) and the position counter — Plapre's stateful
/// model uses `MLState` which can't be cloned from Swift, so there's no
/// cheap warm-start across utterances.
final class PlaprePicoSession: @unchecked Sendable {
    // MARK: - Public stream

    let frames: AsyncThrowingStream<PlaprePicoAudioFrame, Error>

    // MARK: - Private state

    private let manager: PlaprePicoManager
    private let scratch: PlaprePicoInference.DecodeScratch
    private let speakerEmbeddingF32: MLMultiArray

    private let inputStream: AsyncStream<String>
    private let inputContinuation: AsyncStream<String>.Continuation
    private let chunkStream: AsyncStream<ChunkJob>
    private let chunkContinuation: AsyncStream<ChunkJob>.Continuation
    private let framesContinuation:
        AsyncThrowingStream<PlaprePicoAudioFrame, Error>.Continuation

    private var decoderTask: Task<Void, Never>?
    private var audioTask: Task<Void, Never>?

    private let cancelledLock = NSLock()
    private var _cancelled = false
    private var nextUtteranceIndex = 0

    private var cancelled: Bool {
        cancelledLock.lock()
        defer { cancelledLock.unlock() }
        return _cancelled
    }

    private func setCancelled() {
        cancelledLock.lock()
        _cancelled = true
        cancelledLock.unlock()
    }

    // MARK: - Init

    init(manager: PlaprePicoManager, speakerEmbedding: [Float]) throws {
        self.manager = manager
        scratch = try PlaprePicoInference.DecodeScratch(speakerEmbedding: speakerEmbedding)
        speakerEmbeddingF32 = PlaprePicoInference.makeFloat32Array(
            speakerEmbedding,
            shape: [1, PlaprePicoConfig.speakerEmbeddingDimension]
        )

        var inputCont: AsyncStream<String>.Continuation!
        inputStream = AsyncStream { inputCont = $0 }
        inputContinuation = inputCont

        var chunkCont: AsyncStream<ChunkJob>.Continuation!
        chunkStream = AsyncStream { chunkCont = $0 }
        chunkContinuation = chunkCont

        var framesCont: AsyncThrowingStream<PlaprePicoAudioFrame, Error>.Continuation!
        frames = AsyncThrowingStream { framesCont = $0 }
        framesContinuation = framesCont
    }

    // MARK: - Public API (mirrors PocketTtsSession)

    func enqueue(_ text: String) {
        inputContinuation.yield(text)
    }

    func finish() {
        inputContinuation.finish()
    }

    func cancel() async {
        setCancelled()
        inputContinuation.finish()
        chunkContinuation.finish()
        framesContinuation.finish()
        await decoderTask?.value
        await audioTask?.value
    }

    // MARK: - Generator tasks

    func start() {
        // Decoder: text → audio token chunks
        decoderTask = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                for await text in inputStream {
                    if cancelled { break }
                    try decodeUtterance(text: text)
                }
            } catch {
                framesContinuation.finish(throwing: error)
                chunkContinuation.finish()
                return
            }
            // Decoder finished all utterances — signal audio task to drain and exit.
            chunkContinuation.finish()
        }

        // Audio: token chunks → waveform frames.
        //
        // Applies an intra-utterance crossfade between consecutive chunks to
        // mask discontinuities at the vocoder's chunk boundaries (Kanade +
        // Vocoder have no cross-chunk context, so hard edges occur every 100
        // tokens ≈ 4 s of audio). The last `crossfadeSamples` samples of
        // each chunk are held back as `pendingTail` and linearly mixed into
        // the start of the next same-utterance chunk. At utterance boundaries
        // the tail is flushed as-is — the synthesizer inserts silence between
        // utterances so a hard edge there is inaudible anyway.
        audioTask = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            var pendingTail: [Float] = []
            var tailUtterance: Int? = nil

            do {
                for await job in chunkStream {
                    if cancelled { break }

                    let xfade = PlaprePicoConfig.crossfadeSamples
                    let isUtteranceBoundary =
                        tailUtterance != nil && tailUtterance != job.utteranceIndex

                    // Utterance boundary → fade out the held tail and flush
                    // it as the final frame of the previous utterance.
                    if isUtteranceBoundary, let cur = tailUtterance, !pendingTail.isEmpty {
                        Self.applyFadeOut(&pendingTail, length: pendingTail.count)
                        framesContinuation.yield(
                            PlaprePicoAudioFrame(samples: pendingTail, utteranceIndex: cur)
                        )
                        pendingTail = []
                    }

                    // True if this is the first chunk we're processing for
                    // this utterance — i.e. there's no in-utterance tail to
                    // crossfade against. Drives the leading fade-in.
                    let isFirstChunkOfUtterance = pendingTail.isEmpty

                    var samples = try PlaprePicoInference.runAudioChunk(
                        kanade: manager.kanadeModel,
                        vocoder: manager.vocoderModel,
                        audioTokens: job.tokens[...],
                        speakerEmbeddingF32: speakerEmbeddingF32
                    )
                    if cancelled { break }

                    if !pendingTail.isEmpty, samples.count > xfade,
                       pendingTail.count == xfade
                    {
                        // Intra-utterance crossfade: mix pendingTail into the
                        // start of the new chunk to mask the vocoder's chunk
                        // boundary discontinuity.
                        samples.withUnsafeMutableBufferPointer { dst in
                            pendingTail.withUnsafeBufferPointer { tail in
                                for i in 0 ..< xfade {
                                    let fadeOut = Float(xfade - i) / Float(xfade)
                                    let fadeIn = Float(i) / Float(xfade)
                                    dst[i] = tail[i] * fadeOut + dst[i] * fadeIn
                                }
                            }
                        }
                        pendingTail = []
                    } else if isFirstChunkOfUtterance, samples.count > xfade {
                        // First chunk of an utterance — fade in to mask any
                        // vocoder startup transient.
                        Self.applyFadeIn(&samples, length: xfade)
                    }

                    // Hold back the new tail for the next chunk (or for an
                    // end-of-utterance fade-out flush).
                    if samples.count > xfade * 2 {
                        pendingTail = Array(samples.suffix(xfade))
                        samples.removeLast(xfade)
                    }
                    tailUtterance = job.utteranceIndex

                    framesContinuation.yield(
                        PlaprePicoAudioFrame(
                            samples: samples, utteranceIndex: job.utteranceIndex
                        )
                    )
                }

                // Final flush at end-of-stream: fade out the trailing tail
                // of the last utterance so playback ends cleanly.
                if !pendingTail.isEmpty, let cur = tailUtterance {
                    Self.applyFadeOut(&pendingTail, length: pendingTail.count)
                    framesContinuation.yield(
                        PlaprePicoAudioFrame(samples: pendingTail, utteranceIndex: cur)
                    )
                }
            } catch {
                framesContinuation.finish(throwing: error)
                return
            }
            framesContinuation.finish()
        }
    }

    /// Applies a linear fade-in over the first `length` samples of the
    /// buffer (silent → full volume).
    private static func applyFadeIn(_ samples: inout [Float], length: Int) {
        let n = min(length, samples.count)
        guard n > 0 else { return }
        samples.withUnsafeMutableBufferPointer { buf in
            for i in 0 ..< n {
                buf[i] *= Float(i) / Float(n)
            }
        }
    }

    /// Applies a linear fade-out over the last `length` samples of the
    /// buffer (full volume → silent).
    private static func applyFadeOut(_ samples: inout [Float], length: Int) {
        let n = min(length, samples.count)
        guard n > 0 else { return }
        let start = samples.count - n
        samples.withUnsafeMutableBufferPointer { buf in
            for i in 0 ..< n {
                buf[start + i] *= Float(n - i) / Float(n)
            }
        }
    }

    // MARK: - Decode

    /// Runs prefill + autoregressive decode for a single utterance, pushing
    /// `ChunkJob`s onto `chunkContinuation` as they become available.
    /// Does **not** block on Kanade/Vocoder — the audio task drains chunks
    /// concurrently.
    private func decodeUtterance(text: String) throws {
        let uttIdx = nextUtteranceIndex
        nextUtteranceIndex += 1

        // 1. Tokenize. No padding — upstream pads inputSeq then slices back to the
        // real length, so the prefill loop only ever runs over real tokens.
        let raw = manager.tokenizer.encode(text: text, addSpecialTokens: false).map {
            Int32($0)
        }
        let inputTokens: [Int32] =
            [PlaprePicoConfig.eosToken, PlaprePicoConfig.textMarkerToken]
                + raw + [PlaprePicoConfig.audioMarkerToken]
        let inputLen = inputTokens.count

        // 2. Fresh CoreML state + reset masks for this utterance.
        let state = manager.decodeModel.makeState()
        scratch.resetMasks()

        // 3. Prefill (token 0 is the speaker step per upstream). The final step's
        // logits land in `scratch.logits` and are used to sample the first token.
        try PlaprePicoInference.runDecodeStep(
            model: manager.decodeModel, state: state, scratch: scratch,
            ropeCos: manager.ropeCos, ropeSin: manager.ropeSin,
            token: inputTokens[0], pos: 0, isSpeaker: true
        )
        for i in 1 ..< inputLen {
            if cancelled { return }
            try PlaprePicoInference.runDecodeStep(
                model: manager.decodeModel, state: state, scratch: scratch,
                ropeCos: manager.ropeCos, ropeSin: manager.ropeSin,
                token: inputTokens[i], pos: i, isSpeaker: false
            )
        }

        // 4. Sample first generated token from the last prefill step's logits.
        var nextToken = PlaprePicoInference.sampleFromLogits(scratch.logits)

        // 5. Autoregressive decode. Push chunks as they fill — do NOT block on
        // Kanade/Vocoder; that runs on the audio task in parallel.
        let maxTokens = min(
            PlaprePicoConfig.maxGenerationTokens,
            PlaprePicoConfig.maxContextLength - inputLen - 1
        )
        var consecutiveNonAudio = 0
        var chunkBuffer: [Int32] = []
        chunkBuffer.reserveCapacity(PlaprePicoConfig.kanadeChunkSize)

        for step in 0 ..< maxTokens {
            if cancelled { return }
            let pos = inputLen + step
            if nextToken == PlaprePicoConfig.eosToken { break }
            let isAudio =
                nextToken >= PlaprePicoConfig.audioTokenOffset
                    && nextToken <= PlaprePicoConfig.audioTokenMax
            if isAudio {
                consecutiveNonAudio = 0
                chunkBuffer.append(nextToken)
                if chunkBuffer.count == PlaprePicoConfig.kanadeChunkSize {
                    chunkContinuation.yield(
                        ChunkJob(tokens: chunkBuffer, utteranceIndex: uttIdx)
                    )
                    chunkBuffer.removeAll(keepingCapacity: true)
                }
            } else {
                consecutiveNonAudio += 1
                if consecutiveNonAudio >= PlaprePicoConfig.nonAudioStopThreshold { break }
            }

            // Feed token forward; new logits land in scratch.logits. Sample next.
            try PlaprePicoInference.runDecodeStep(
                model: manager.decodeModel, state: state, scratch: scratch,
                ropeCos: manager.ropeCos, ropeSin: manager.ropeSin,
                token: nextToken, pos: pos, isSpeaker: false
            )
            nextToken = PlaprePicoInference.sampleFromLogits(scratch.logits)
        }

        // 6. Flush any remaining audio tokens as a final (possibly partial) chunk.
        if !chunkBuffer.isEmpty {
            chunkContinuation.yield(
                ChunkJob(tokens: chunkBuffer, utteranceIndex: uttIdx)
            )
        }

        AppLogger.info("Plapre: decoded utt=\(public: uttIdx)", category: .general)
    }
}
#endif
