/// Accumulates audio frames during synthesis startup and releases them
/// once a target duration is reached.
///
/// This gives `AVAudioPlayerNode` a small head-start queue so transient
/// model-generation stalls don't starve the player and cause audible dropouts.
struct PlaybackBuffer {
    /// Target buffer duration before playback starts (seconds).
    let targetDuration: TimeInterval

    /// Sample rate of frames appended to this buffer (Hz).
    let sampleRate: Double

    /// Accumulated raw audio frames before the threshold is crossed.
    private var buffer: [[Float]] = []

    /// Total number of individual samples accumulated so far.
    private var totalSampleCount: Int = 0

    /// Whether playback has already started (threshold crossed).
    private var hasStarted: Bool = false

    /// Create a playback buffer.
    ///
    /// - Parameters:
    ///   - targetDuration: Seconds of audio to accumulate before the first
    ///     flush (default 0.25 s).
    ///   - sampleRate: Sample rate of the incoming frames (Hz).
    init(targetDuration: TimeInterval = 0.25, sampleRate: Double) {
        self.targetDuration = targetDuration
        self.sampleRate = sampleRate
    }

    /// Append a frame of audio.
    ///
    /// - Returns: The full list of buffered frames when the threshold is first
    ///   crossed, a single-element array containing just `samples` after the
    ///   threshold is crossed, or `nil` while still accumulating below the
    ///   target duration.
    mutating func append(samples: [Float]) -> [[Float]]? {
        guard !samples.isEmpty else { return nil }

        if hasStarted {
            // Playback already started — pass through immediately.
            return [samples]
        }

        buffer.append(samples)
        totalSampleCount += samples.count

        if accumulatedDuration >= targetDuration {
            hasStarted = true
            let accumulated = buffer
            buffer = []
            totalSampleCount = 0
            return accumulated
        }

        return nil
    }

    /// Flush any remaining buffered frames.
    ///
    /// Call this when the stream ends so the tail of the audio isn't dropped.
    /// - Returns: All remaining buffered frames, or an empty array if none.
    mutating func flush() -> [[Float]] {
        let remaining = buffer
        buffer = []
        totalSampleCount = 0
        hasStarted = true
        return remaining
    }

    // MARK: - Private

    private var accumulatedDuration: TimeInterval {
        TimeInterval(totalSampleCount) / sampleRate
    }
}
