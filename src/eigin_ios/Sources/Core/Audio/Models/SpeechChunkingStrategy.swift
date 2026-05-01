/// How a `DefaultSpeechService` should split text into utterances before
/// handing them to a `SpeechSynthesizing` backend.
///
/// Three semantically distinct policies — they differ both in *where* they
/// split and in *how big* the resulting chunks are.
enum SentenceChunking: Equatable {
    /// Never split mid-paragraph. Each paragraph (`\n\n` separated) becomes
    /// one utterance. Best for engines whose synthesizer streams audio fast
    /// enough that finer chunking adds latency without improving pacing —
    /// historically Pocket TTS in one-shot mode.
    case paragraphsOnly

    /// Split at every sentence boundary as soon as `minSize` characters have
    /// accumulated since the last split. Eager — emits each sentence as its
    /// own utterance with natural inter-sentence pacing. Best for engines
    /// that restart their decoder state per utterance.
    case eager(minSize: Int)

    /// Accumulate until the buffer reaches `minBuffer` characters, then split
    /// at the **last** complete sentence boundary in the buffer. Batches
    /// multiple short sentences into one utterance. Best for streaming text
    /// from an LLM into engines with persistent sessions, where frequent
    /// restarts hurt more than slightly delayed first-sentence playback.
    case bufferedBatch(minBuffer: Int)
}

/// A `SpeechEngineProvider`'s preferred chunking policy. Holds a separate
/// `SentenceChunking` for one-shot vs streaming because the right answer
/// often differs between the two: for an engine like Pocket TTS, one-shot
/// playback can keep paragraphs intact while streaming benefits from
/// sentence-level batching to start audio sooner.
struct SpeechChunkingStrategy: Equatable {
    /// Strategy applied by `SpeechService.speak()`.
    let oneShot: SentenceChunking
    /// Strategy applied by `SpeechService.feedDelta()` / `finish()`.
    let streaming: SentenceChunking

    /// Eager per-sentence splitting in both modes. For engines that restart
    /// their decoder state per utterance and benefit from natural sentence
    /// pacing — Plapre Pico.
    static let eager = SpeechChunkingStrategy(
        oneShot: .eager(minSize: 20),
        streaming: .eager(minSize: 20)
    )

    /// Historical default: never subdivide paragraphs in one-shot mode, and
    /// batch sentences into ~200-char utterances during streaming. For
    /// engines with persistent multi-utterance sessions where restart
    /// overhead is non-trivial — Pocket TTS and the system engine.
    static let buffered = SpeechChunkingStrategy(
        oneShot: .paragraphsOnly,
        streaming: .bufferedBatch(minBuffer: 200)
    )
}
