/// Smooths utterance boundaries in the post-resample audio stream.
///
/// Holds the most recent chunk of the current utterance until either more of
/// that utterance or the next utterance arrives, so the seam between
/// utterances can be smoothed instead of butted together.
///
/// Two boundary modes:
/// - **Crossfade** (default): the previous tail is crossfaded into the new
///   utterance's head, for engines that play utterances back to back.
/// - **Faded**: the tail fades out to silence and the new head fades in,
///   for engines that insert their own inter-utterance silence.
///
/// The first chunk of a stream fades in from silence and the held tail fades
/// out at end of stream in both modes.
///
/// In crossfade mode the join shortens the timeline by the overlap length.
/// Adds at most one chunk of latency to the tail of each utterance.
final class SpeechFade {
    private let fadeCount: Int
    private let crossfadeAtBoundary: Bool
    private var held: (samples: [Float], utteranceIndex: Int)?
    private var started = false

    /// - Parameters:
    ///   - sampleRate: sample rate of the audio after resampling (48 kHz).
    ///   - fadeDuration: crossfade (or fade-out/fade-in) length at utterance
    ///     boundaries and at stream start/end.
    ///   - crossfadeAtBoundary: see the mode discussion above.
    init(
        sampleRate: Double,
        fadeDuration: TimeInterval = 0.030,
        crossfadeAtBoundary: Bool = true
    ) {
        fadeCount = max(1, Int(sampleRate * fadeDuration))
        self.crossfadeAtBoundary = crossfadeAtBoundary
    }

    /// Feeds one resampled chunk in. Returns the chunks ready to schedule,
    /// in play order.
    func append(samples: [Float], utteranceIndex: Int) -> [[Float]] {
        guard !samples.isEmpty else { return [] }
        var chunk = samples
        if !started {
            started = true
            Self.applyRamp(&chunk, count: min(fadeCount, chunk.count), fadeIn: true)
            held = (chunk, utteranceIndex)
            return []
        }
        guard let current = held else {
            held = (chunk, utteranceIndex)
            return []
        }
        if current.utteranceIndex == utteranceIndex {
            held = (chunk, utteranceIndex)
            return [current.samples]
        }

        if crossfadeAtBoundary {
            let fade = min(fadeCount, current.samples.count, chunk.count)
            // An overlap of one sample can't mix both sides — butt join.
            guard fade >= 2 else {
                held = (chunk, utteranceIndex)
                return [current.samples]
            }
            let seam = Self.crossfade(
                tail: current.samples.suffix(fade),
                head: chunk.prefix(fade)
            )
            held = (Array(chunk.dropFirst(fade)), utteranceIndex)
            return [Array(current.samples.dropLast(fade)), seam]
        }

        // Faded boundary: release the tail fading out, keep the new chunk
        // fading in.
        var tail = current.samples
        Self.applyRamp(&tail, count: min(fadeCount, tail.count), fadeIn: false)
        Self.applyRamp(&chunk, count: min(fadeCount, chunk.count), fadeIn: true)
        held = (chunk, utteranceIndex)
        return [tail]
    }

    /// Releases the held tail at end of stream, fading out to silence.
    func flush() -> [[Float]] {
        guard var tail = held else { return [] }
        held = nil
        started = false
        Self.applyRamp(
            &tail.samples,
            count: min(fadeCount, tail.samples.count),
            fadeIn: false
        )
        return [tail.samples]
    }

    /// Linear crossfade: the tail tapers down as the head ramps up.
    private static func crossfade(tail: ArraySlice<Float>, head: ArraySlice<Float>)
        -> [Float]
    {
        let count = tail.count
        var out = [Float](repeating: 0, count: count)
        for k in 0 ..< count {
            let t = Float(k) / Float(max(count - 1, 1))
            out[k] = tail[tail.startIndex + k] * (1 - t)
                + head[head.startIndex + k] * t
        }
        return out
    }

    /// Linear ramp over the first (`fadeIn`) or last fade-out `count`
    /// samples, in place. No-op for `count < 2`.
    private static func applyRamp(_ samples: inout [Float], count: Int, fadeIn: Bool) {
        guard count > 1 else { return }
        for k in 0 ..< count {
            let t = Float(k) / Float(count - 1)
            let weight = fadeIn ? t : 1 - t
            let index = fadeIn ? k : samples.count - count + k
            samples[index] *= weight
        }
    }
}
