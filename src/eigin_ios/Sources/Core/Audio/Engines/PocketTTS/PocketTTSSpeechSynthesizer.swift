#if !targetEnvironment(simulator)
@preconcurrency import AVFoundation
import FluidAudio

/// Speech synthesizer backed by Pocket TTS via FluidAudio CoreML.
///
/// Uses `PocketTtsSession` for persistent voice KV cache across utterances.
/// The expensive voice prefill (~125 tokens) happens once per session;
/// subsequent utterances only pay the text prefill cost. Mimi decoder
/// state persists across utterances for seamless audio continuity.
@MainActor
final class PocketTTSSpeechSynthesizer: SpeechSynthesizing, @unchecked Sendable {
    var onFinish: ((_ text: String) -> Void)?
    var onCancel: ((_ text: String) -> Void)?
    var onWillSpeak: ((_ range: NSRange, _ text: String) -> Void)?

    private let modelManager: PocketTTSModelManager
    private let voiceName: String

    /// Audio output that resumes across route changes without repeating.
    private var resumablePlayer: ResumableAudioPlayer?

    // Session state
    private var session: PocketTtsSession?
    private var utteranceTexts: [Int: String] = [:]
    private var nextUtteranceIndex: Int = 0

    // Generation state
    private var pendingTexts: [String] = []
    private var generationTask: Task<Void, Never>?
    /// Tracks the in-flight session cancellation so `startGenerating()` can
    /// await it before creating a new session — prevents Neural Engine contention.
    private var sessionCancelTask: Task<Void, Never>?
    /// Set by `finishSpeaking()` when the session doesn't exist yet.
    /// The generation task checks this after enqueuing texts.
    private var finishWhenReady = false
    /// True while a generation task is running (session creation through frame reading).
    /// Prevents `speak()` from spawning duplicate generation tasks.
    private var isGenerationActive = false
    /// Incremented on stopSpeaking(). Each task captures the current ID and
    /// exits if it no longer matches — guarantees serial model access.
    private var generationID: Int = 0

    /// Playback tracking: each scheduled buffer is tagged with its utterance text.
    /// When a buffer's completion fires, we know that utterance's audio has played.
    private var scheduledUtterances: [String] = []

    /// Playback buffering: accumulate a startup buffer so transient
    /// model-generation stalls don't starve the player node queue.
    private var playbackBuffer: PlaybackBuffer?

    // Engine runs at system rate (48kHz); model outputs at 24kHz.
    private nonisolated static let outputSampleRate: Double = 48000
    private nonisolated static let modelSampleRate: Double = 24000
    private var converter: AVAudioConverter?

    init(modelManager: PocketTTSModelManager, voiceName: String = "alba") {
        self.modelManager = modelManager
        self.voiceName = voiceName
    }

    func speak(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            onFinish?(text)
            return
        }

        pendingTexts.append(text)

        if let session {
            // Session already active — enqueue directly
            utteranceTexts[nextUtteranceIndex] = text
            nextUtteranceIndex += 1
            session.enqueue(text)
        } else if !isGenerationActive {
            // No session and no pending generation — start one.
            // If a generation task is already running, it will pick up
            // the text from pendingTexts when it enqueues.
            startGenerating()
        }
    }

    /// Fails the current generation loudly: drains every pending text without
    /// a live finish marker through `onFinish` (speech is skipped) so the
    /// caller's completion bookkeeping drains and the live-call turn never
    /// wedges on a silently dropped finish callback. Texts whose markers are
    /// still scheduled in the player are left alone — their markers will fire
    /// normally, and draining them here would double-fire.
    private func failGeneration() {
        var orphans = pendingTexts
        // Remove one entry per live marker, so duplicate texts keep their
        // unmatched copies.
        for text in scheduledUtterances {
            if let index = orphans.firstIndex(of: text) {
                orphans.remove(at: index)
            }
        }
        pendingTexts.removeAll()
        scheduledUtterances.removeAll()
        utteranceTexts.removeAll()
        nextUtteranceIndex = 0
        finishWhenReady = false
        isGenerationActive = false
        playbackBuffer = nil
        for text in orphans {
            onFinish?(text)
        }
    }

    func finishSpeaking() {
        if let session {
            session.finish()
        } else {
            // Session not yet created — flag it so the generation task
            // finishes the session after enqueuing texts.
            finishWhenReady = true
        }
    }

    func prepare() async {
        try? await modelManager.load()
    }

    func stopSpeaking() {
        generationID += 1
        isGenerationActive = false
        generationTask?.cancel()

        playbackBuffer = nil
        // finish() is nonisolated — stops new generation immediately.
        // cancel() awaits the generation task — store so startGenerating()
        // can wait for inference to fully stop before creating a new session.
        session?.finish()
        let sessionToCancel = session
        sessionCancelTask = Task { await sessionToCancel?.cancel() }
        session = nil
        utteranceTexts.removeAll()
        nextUtteranceIndex = 0

        pendingTexts.removeAll()
        scheduledUtterances.removeAll()
        finishWhenReady = false
        tearDownAudio()
        modelManager.scheduleUnload()
    }

    /// Rebuild the output engine on the new route, resuming the unplayed tail
    /// of the current utterance. The in-flight fragment is clipped rather
    /// than replayed, so nothing repeats and the finish markers still fire,
    /// keeping the caller's turn bookkeeping intact.
    func handleRouteChange() {
        resumablePlayer?.handleRouteChange()
    }

    // MARK: - Audio Engine

    private func ensureEngineRunning() {
        guard resumablePlayer == nil else { return }
        let player = ResumableAudioPlayer(sampleRate: Self.outputSampleRate)
        do {
            try player.start()
        } catch {
            return // Generation will fail gracefully.
        }

        // Converter: model sample rate → engine sample rate
        let inputFormat = AVAudioFormat(
            standardFormatWithSampleRate: Self.modelSampleRate,
            channels: 1
        )!
        let outputFormat = AVAudioFormat(
            standardFormatWithSampleRate: Self.outputSampleRate,
            channels: 1
        )!
        converter = AVAudioConverter(from: inputFormat, to: outputFormat)
        resumablePlayer = player
    }

    /// Full teardown — stops engine, releases resources.
    private func tearDownAudio() {
        resumablePlayer?.stop()
        resumablePlayer = nil
        converter = nil
    }

    // MARK: - Generation Pipeline

    private func startGenerating() {
        let previousTask = generationTask
        let previousCancelTask = sessionCancelTask
        let myID = generationID
        isGenerationActive = true

        generationTask = Task(priority: .userInitiated) { [weak self] in
            defer { Task { @MainActor in self?.isGenerationActive = false } }

            // Wait for any previous session cancellation and generation to fully exit.
            // This ensures the Neural Engine is released before we start a new session.
            await previousCancelTask?.value
            await previousTask?.value

            guard let self else { return }

            await MainActor.run {
                self.ensureEngineRunning()
            }

            let converter: AVAudioConverter? = await MainActor.run { self.converter }

            await MainActor.run {
                self.playbackBuffer = PlaybackBuffer(sampleRate: Self.outputSampleRate)
            }

            // Load model into memory (idempotent — no-op if already loaded, cancels pending
            // unload).
            do {
                try await modelManager.load()
            } catch {
                // Nothing was spoken — fail loudly so the caller's counters drain.
                if await MainActor.run(body: { self.generationID == myID }) {
                    await MainActor.run { self.failGeneration() }
                }
                return
            }

            // Create session (voice prefill happens once here).
            guard let manager = await MainActor.run(body: { self.modelManager.manager })
            else { return }
            let session: PocketTtsSession
            do {
                session = try await manager.makeSession(voice: voiceName)
            } catch {
                if await MainActor.run(body: { self.generationID == myID }) {
                    await MainActor.run { self.failGeneration() }
                }
                return
            }

            await MainActor.run {
                self.session = session
            }

            // Enqueue all pending texts into the session.
            // If finishSpeaking() was called before the session existed,
            // finish the session now so the frame stream ends after these texts.
            await MainActor.run {
                for text in self.pendingTexts {
                    self.utteranceTexts[self.nextUtteranceIndex] = text
                    self.nextUtteranceIndex += 1
                    session.enqueue(text)
                }
                if self.finishWhenReady {
                    self.finishWhenReady = false
                    session.finish()
                }
            }

            // Read frames from the session stream.
            var previousUtteranceIndex: Int = -1
            var willSpeakFired: Set<Int> = []
            // Utterance indices whose finish marker has been scheduled, so the
            // end-of-stream sweep below only marks utterances that never got one.
            var finishedUtterances: Set<Int> = []

            do {
                for try await frame in session.frames {
                    try Task.checkCancellation()
                    guard await MainActor.run(body: { self.generationID == myID }) else { break }

                    let uttIdx = frame.utteranceIndex ?? max(previousUtteranceIndex, 0)

                    // Utterance boundary — schedule finish for previous, willSpeak for new
                    if uttIdx != previousUtteranceIndex {
                        if previousUtteranceIndex >= 0,
                           !finishedUtterances.contains(previousUtteranceIndex)
                        {
                            finishedUtterances.insert(previousUtteranceIndex)
                            let prevText = await MainActor
                                .run { self.utteranceTexts[previousUtteranceIndex] }
                            if let prevText {
                                await MainActor.run {
                                    self.scheduleFinishMarker(for: prevText)
                                }
                            }
                        }
                        previousUtteranceIndex = uttIdx
                    }

                    // Buffer audio frames; start playback once enough headroom
                    // has accumulated to mask transient generation stalls.
                    let samples = frame.samples
                    if !samples.isEmpty, let converter {
                        if let resampled = Self.resample(samples, using: converter) {
                            let frames = await MainActor.run {
                                self.playbackBuffer?.append(samples: resampled)
                            }
                            if let frames {
                                for frame in frames {
                                    if let buffer = Self.createBuffer(from: frame) {
                                        await MainActor.run {
                                            self.resumablePlayer?.schedule(buffer)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Schedule willSpeak on first frame of each utterance
                    if !willSpeakFired.contains(uttIdx) {
                        willSpeakFired.insert(uttIdx)
                        let text = await MainActor.run { self.utteranceTexts[uttIdx] }
                        if let text {
                            await MainActor.run {
                                self.scheduleTextMarker(text: text, charCount: text.count)
                            }
                        }
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                guard await MainActor.run(body: { self.generationID == myID }) else { return }
            }

            // Flush any remaining buffered frames so the tail isn't dropped.
            let tailFrames = await MainActor.run {
                self.playbackBuffer?.flush() ?? []
            }
            for frame in tailFrames {
                if let buffer = Self.createBuffer(from: frame) {
                    await MainActor.run {
                        self.resumablePlayer?.schedule(buffer)
                    }
                }
            }

            // Stream ended — close the session before the sweep runs, so a
            // speak() landing in the sweep's suspension hops starts a fresh
            // generation (whose enqueue loop reads pendingTexts) instead of
            // enqueueing into the finished session, which would orphan text.
            // Then schedule a finish marker for every utterance that never got
            // one. Normal path: just the last utterance. Also covers frames
            // without utterance indices and streams that ended without frames
            // at all, which previously dropped onFinish and wedged the turn.
            guard await MainActor.run(body: { self.generationID == myID }) else { return }
            let unmatched = await MainActor.run {
                self.session = nil
                self.isGenerationActive = false
                return self.utteranceTexts
                    .sorted { $0.key < $1.key }
                    .filter { !finishedUtterances.contains($0.key) }
                    .map { (index: $0.key, text: $0.value) }
            }
            for entry in unmatched {
                guard await MainActor.run(body: { self.generationID == myID }) else { return }
                await MainActor.run {
                    self.scheduleFinishMarker(for: entry.text)
                }
            }
            await MainActor.run {
                self.session = nil
                self.utteranceTexts.removeAll()
                self.nextUtteranceIndex = 0
                self.playbackBuffer = nil
            }
        }
    }

    // MARK: - Audio Processing (nonisolated — runs off main actor)

    private nonisolated static func createBuffer(from samples: [Float]) -> AVAudioPCMBuffer? {
        guard !samples.isEmpty else { return nil }
        let format = AVAudioFormat(standardFormatWithSampleRate: outputSampleRate, channels: 1)!
        let frameCount = AVAudioFrameCount(samples.count)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
        else { return nil }
        buffer.frameLength = frameCount
        samples.withUnsafeBufferPointer { src in
            buffer.floatChannelData![0].update(from: src.baseAddress!, count: samples.count)
        }
        return buffer
    }

    private nonisolated static func resample(
        _ samples: [Float],
        using converter: AVAudioConverter
    ) -> [Float]? {
        let inputFormat = converter.inputFormat
        let outputFormat = converter.outputFormat
        let ratio = outputFormat.sampleRate / inputFormat.sampleRate

        let inputFrameCount = AVAudioFrameCount(samples.count)
        guard let inputBuffer = AVAudioPCMBuffer(
            pcmFormat: inputFormat,
            frameCapacity: inputFrameCount
        )
        else { return nil }
        inputBuffer.frameLength = inputFrameCount
        samples.withUnsafeBufferPointer { src in
            inputBuffer.floatChannelData![0].update(from: src.baseAddress!, count: samples.count)
        }

        let outputFrameCount = AVAudioFrameCount(Double(samples.count) * ratio + 1)
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: outputFrameCount
        )
        else { return nil }

        var error: NSError?
        nonisolated(unsafe) var consumed = false
        nonisolated(unsafe) let input = inputBuffer
        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return input
        }

        guard error == nil, outputBuffer.frameLength > 0 else { return nil }

        let ptr = outputBuffer.floatChannelData![0]
        return Array(UnsafeBufferPointer(start: ptr, count: Int(outputBuffer.frameLength)))
    }

    /// Schedules a silent buffer that fires `onWillSpeak` when playback reaches it.
    private func scheduleTextMarker(text: String, charCount: Int) {
        guard let resumablePlayer else { return }
        let myID = generationID
        let format = AVAudioFormat(
            standardFormatWithSampleRate: Self.outputSampleRate,
            channels: 1
        )!
        let marker = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1)!
        marker.frameLength = 1
        marker.floatChannelData![0][0] = 0

        // Completion runs on the main actor via ResumableAudioPlayer.
        resumablePlayer.schedule(marker) { [weak self] in
            guard let self, generationID == myID else { return }
            onWillSpeak?(NSRange(location: 0, length: charCount), text)
        }
    }

    private func scheduleFinishMarker(for text: String) {
        guard let resumablePlayer else {
            onFinish?(text)
            return
        }

        scheduledUtterances.append(text)

        let myID = generationID
        let format = AVAudioFormat(
            standardFormatWithSampleRate: Self.outputSampleRate,
            channels: 1
        )!
        let marker = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1)!
        marker.frameLength = 1
        marker.floatChannelData![0][0] = 0

        resumablePlayer.schedule(marker) { [weak self] in
            guard let self, generationID == myID else { return }
            if let idx = scheduledUtterances.firstIndex(of: text) {
                scheduledUtterances.remove(at: idx)
            }
            if let idx = pendingTexts.firstIndex(of: text) {
                pendingTexts.remove(at: idx)
            }
            if scheduledUtterances.isEmpty, pendingTexts.isEmpty {
                modelManager.scheduleUnload()
            }

            onFinish?(text)
        }
    }
}

#endif
