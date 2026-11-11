@preconcurrency import AVFoundation

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

    private let makeSession: @MainActor () async throws -> any PocketTTSSession
    private let prepareModel: @MainActor () async -> Void
    private let scheduleUnload: @MainActor () -> Void
    private let audioEnabled: Bool

    /// Audio output that resumes across route changes without repeating.
    private var resumablePlayer: ResumableAudioPlayer?

    // Session state
    private var session: (any PocketTTSSession)?
    private var sessionInputFinished = false
    private var utteranceTexts: [Int: String] = [:]
    private var nextUtteranceIndex: Int = 0

    /// Generation state
    private var pendingTexts: [String] = []
    /// Text not yet assigned to a session, including text arriving while one drains.
    private var queuedTexts: [String] = []
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

    /// Output processing for this engine: loudness makeup and top-end presence.
    /// Values are placeholders — tuned by ear across the voice catalog.
    private nonisolated static let dspConfig = SpeechDSPConfig(
        makeupGainDecibels: 3,
        highShelf: .init(cornerFrequency: 5000, gainDecibels: 3)
    )

    private var converter: AVAudioConverter?

    init(
        makeSession: @escaping @MainActor () async throws -> any PocketTTSSession,
        prepare: @escaping @MainActor () async -> Void = {},
        scheduleUnload: @escaping @MainActor () -> Void = {},
        audioEnabled: Bool = true
    ) {
        self.makeSession = makeSession
        prepareModel = prepare
        self.scheduleUnload = scheduleUnload
        self.audioEnabled = audioEnabled
    }

    func speak(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            onFinish?(text)
            return
        }

        pendingTexts.append(text)

        if let session, !sessionInputFinished {
            utteranceTexts[nextUtteranceIndex] = text
            nextUtteranceIndex += 1
            session.enqueue(text)
        } else {
            queuedTexts.append(text)
            if !isGenerationActive {
                startGenerating()
            }
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
        queuedTexts.removeAll()
        scheduledUtterances.removeAll()
        utteranceTexts.removeAll()
        nextUtteranceIndex = 0
        finishWhenReady = false
        playbackBuffer = nil
        for text in orphans {
            onFinish?(text)
        }
    }

    func finishSpeaking() {
        if let session, !sessionInputFinished {
            sessionInputFinished = true
            session.finish()
        } else if session == nil || !queuedTexts.isEmpty {
            finishWhenReady = true
        }
    }

    func prepare() async {
        await prepareModel()
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
        sessionInputFinished = false
        utteranceTexts.removeAll()
        nextUtteranceIndex = 0

        pendingTexts.removeAll()
        queuedTexts.removeAll()
        scheduledUtterances.removeAll()
        finishWhenReady = false
        tearDownAudio()
        scheduleUnload()
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
        guard audioEnabled, resumablePlayer == nil else { return }
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
            guard let self else { return }
            defer { generationEnded(id: myID) }

            // Serialize inference, including startup that was canceled before session creation.
            await previousCancelTask?.value
            await previousTask?.value
            guard generationID == myID, !Task.isCancelled else { return }

            ensureEngineRunning()
            let converter = converter
            playbackBuffer = PlaybackBuffer(sampleRate: Self.outputSampleRate)
            let dsp = SpeechDSPProcessor(
                config: Self.dspConfig,
                sampleRate: Self.outputSampleRate
            )
            let fade = SpeechFade(sampleRate: Self.outputSampleRate)

            let session: any PocketTTSSession
            do {
                session = try await makeSession()
            } catch {
                if generationID == myID, !Task.isCancelled {
                    failGeneration()
                }
                return
            }
            guard generationID == myID, !Task.isCancelled else {
                await session.cancel()
                return
            }

            self.session = session
            sessionInputFinished = false
            for text in queuedTexts {
                utteranceTexts[nextUtteranceIndex] = text
                nextUtteranceIndex += 1
                session.enqueue(text)
            }
            queuedTexts.removeAll()
            if finishWhenReady {
                finishWhenReady = false
                sessionInputFinished = true
                session.finish()
            }

            var previousUtteranceIndex = -1
            var willSpeakFired: Set<Int> = []
            var finishedUtterances: Set<Int> = []
            do {
                for try await frame in session.frames {
                    guard generationID == myID, !Task.isCancelled else { return }
                    let uttIdx = frame.utteranceIndex ?? max(previousUtteranceIndex, 0)
                    var pendingFinishText: String?
                    if uttIdx != previousUtteranceIndex {
                        if previousUtteranceIndex >= 0,
                           !finishedUtterances.contains(previousUtteranceIndex)
                        {
                            finishedUtterances.insert(previousUtteranceIndex)
                            pendingFinishText = utteranceTexts[previousUtteranceIndex]
                        }
                        previousUtteranceIndex = uttIdx
                    }

                    if !frame.samples.isEmpty, let converter,
                       var resampled = Self.resample(frame.samples, using: converter)
                    {
                        dsp.process(&resampled)
                        for chunk in fade.append(samples: resampled, utteranceIndex: uttIdx) {
                            appendAndSchedule(chunk)
                        }
                    }
                    if let pendingFinishText {
                        scheduleFinishMarker(for: pendingFinishText)
                    }
                    guard generationID == myID, !Task.isCancelled else { return }
                    if !willSpeakFired.contains(uttIdx) {
                        willSpeakFired.insert(uttIdx)
                        if let text = utteranceTexts[uttIdx] {
                            scheduleTextMarker(text: text, charCount: text.count)
                        }
                    }
                }
            } catch {
                guard generationID == myID, !Task.isCancelled else { return }
            }
            guard generationID == myID, !Task.isCancelled else { return }

            self.session = nil
            for chunk in fade.flush() {
                appendAndSchedule(chunk)
            }
            for frame in playbackBuffer?.flush() ?? [] {
                if let buffer = Self.createBuffer(from: frame) {
                    resumablePlayer?.schedule(buffer)
                }
            }

            // Account for each session's text before allowing another session to start.
            let unmatched = utteranceTexts.sorted { $0.key < $1.key }
                .filter { !finishedUtterances.contains($0.key) }
            for entry in unmatched {
                guard generationID == myID, !Task.isCancelled else { return }
                scheduleFinishMarker(for: entry.value)
            }
        }
    }

    /// Releases only the owning task's state, then starts text queued during its drain.
    private func generationEnded(id: Int) {
        guard generationID == id else { return }
        session = nil
        sessionInputFinished = false
        utteranceTexts.removeAll()
        nextUtteranceIndex = 0
        playbackBuffer = nil
        isGenerationActive = false
        if !queuedTexts.isEmpty {
            startGenerating()
        }
    }

    // MARK: - Audio Processing

    /// Appends a resampled chunk to the playback buffer and schedules any
    /// frames it released onto the player node.
    private func appendAndSchedule(_ chunk: [Float]) {
        let frames = playbackBuffer?.append(samples: chunk) ?? []
        for frame in frames {
            if let buffer = Self.createBuffer(from: frame) {
                resumablePlayer?.schedule(buffer)
            }
        }
    }

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
            if let index = pendingTexts.firstIndex(of: text) {
                pendingTexts.remove(at: index)
            }
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
                scheduleUnload()
            }

            onFinish?(text)
        }
    }
}
