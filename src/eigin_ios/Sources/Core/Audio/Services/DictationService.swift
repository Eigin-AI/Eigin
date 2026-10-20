@preconcurrency import AVFoundation
import Observation
import Speech
import UIKit

/// On-device speech recognition service for dictating messages.
protocol DictationService {
    var state: AppDictationState { get }
    var transcription: String { get }
    var error: String? { get }
    func start()
    func stop()
    /// Stops capturing, finalizes the analyzer, and returns the complete
    /// transcription — including the tail that hadn't been transcribed yet.
    /// Always ends in `.idle`.
    @MainActor
    func finish() async -> String
    func setLocale(_ locale: Locale)
    func setContextualStrings(_ strings: [String])
}

/// The current state of the dictation pipeline.
enum AppDictationState: Equatable {
    case idle
    case preparing
    case listening
    case transcribing
    case error(String)

    var isActive: Bool {
        switch self {
        case .preparing, .listening, .transcribing: true
        default: false
        }
    }
}

/// Default implementation using SpeechAnalyzer with on-device recognition.
/// Prefers ``SpeechTranscriber`` (Apple Intelligence model) on capable devices,
/// falls back to ``DictationTranscriber`` on older hardware.
@Observable
final class DefaultDictationService: NSObject, DictationService, @unchecked Sendable {
    private(set) var state: AppDictationState = .idle
    private(set) var transcription = ""
    private(set) var error: String?
    /// When true, `stop()` keeps the audio session active (used by live call mode).
    var keepSessionActive = false
    private let audioEngine = AVAudioEngine()
    private var analyzer: SpeechAnalyzer?
    private var resultTask: Task<Void, Never>?
    private var analyzerTask: Task<Void, Never>?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var rawContinuation: AsyncStream<AVAudioPCMBuffer>.Continuation?
    private var converter: BufferConverter?

    /// Text preserved from before a route-change restart.
    private var committedTranscription = ""
    /// Words to bias speech recognition toward (names, jargon, etc.).
    private var contextualStrings: [String] = []
    /// The locale to use for recognition.
    private var locale: Locale = .current
    /// Incremented on each start()/stop() cycle so stale callbacks are ignored.
    private var generation = 0
    /// True while recovering from an audio route change. Callers (e.g.
    /// LiveCallService) can check this to avoid premature silence detection.
    private var hasReceivedTranscription = false

    override init() {
        super.init()
    }

    func setLocale(_ locale: Locale) {
        let wasRecording = isRecording
        if wasRecording { stop() }
        self.locale = locale
        if wasRecording { start() }
    }

    func setContextualStrings(_ strings: [String]) {
        contextualStrings = strings
        pushContextualStrings()
    }

    /// A context carrying the current vocabulary; empty list clears it.
    private func makeAnalysisContext() -> AnalysisContext {
        let context = AnalysisContext()
        if !contextualStrings.isEmpty {
            context.contextualStrings[.general] = contextualStrings
        }
        return context
    }

    /// Hands the vocabulary to a running analyzer so the recognizer biases
    /// toward it even though it's not in the system vocabulary (iOS 26
    /// `AnalysisContext`).
    private func pushContextualStrings() {
        guard let analyzer else { return }
        let context = makeAnalysisContext()
        Task {
            do {
                try await analyzer.setContext(context)
            } catch {
                AppLogger.warning(
                    "Failed to set speech analysis context: \(private: error.localizedDescription)",
                    category: .general
                )
            }
        }
    }

    var isRecovering: Bool {
        state == .preparing
    }

    var isRecording: Bool {
        state.isActive
    }

    /// Rebuilds the audio graph after a route change or interruption, preserving
    /// the committed transcription so the turn continues seamlessly. Driven by
    /// ``AudioRouteCoordinator`` during live calls and by this service's own
    /// observers during standalone dictation. Must be called on the main actor.
    func recover() {
        guard isRecording else { return }
        tearDownAudio()
        generation += 1
        committedTranscription = transcription
        state = .preparing
        let gen = generation
        Task { [weak self] in
            await self?.beginRecording(generation: gen)
        }
    }

    /// Stops capturing, finalizes the analyzer, and returns the complete
    /// transcription — the buffered backlog plus the flushed tail. Bounded by
    /// ``finalizationTimeout``; returns the latest transcription if the
    /// analyzer doesn't finish in time. Always tears down to `.idle`.
    /// Upper bound on waiting for analyzer startup when finishing during
    /// `.preparing` (a very fast send). Keeps the user-visible delay small
    /// while letting the buffered backlog still be transcribed.
    private static let startupGrace: Duration = .seconds(1)

    /// Upper bound on waiting for the tail transcription when finishing. A
    /// short tail typically finalizes in well under a second; the cap only
    /// bounds the worst case so sending still feels immediate.
    private static let finalizationTimeout: Duration = .seconds(1.2)

    /// Interval for the bounded readiness and completion polls below — long
    /// enough not to spam, short enough not to delay a send noticeably.
    private static let pollInterval: Duration = .milliseconds(50)

    @MainActor
    func finish() async -> String {
        guard state.isActive else { return transcription }

        // Analyzer still coming up: give it a brief bounded chance so the
        // audio buffered during setup gets transcribed too, instead of
        // hard-stopping and dropping the whole backlog.
        await waitForAnalyzerReadiness(timeout: Self.startupGrace)

        guard state.isActive else { return transcription }
        if case .preparing = state {
            // Still not ready after the grace period — nothing to finalize.
            stop()
            return transcription
        }

        // No new audio enters the pipeline from here, and nowhere is left
        // to hold it: finish the raw stream so the feeder drains the
        // backlog and ends the analyzer input.
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        rawContinuation?.finish()

        // Finalize through end-of-input so volatile tail results become final.
        let finalized = await withTimeout(Self.finalizationTimeout) {
            await self.drainAndFinalize()
            return await MainActor.run { self.transcription }
        }

        if finalized != nil {
            finishTeardown()
        } else {
            // Timed out — tear down in the background so the next start is fresh.
            Task { @MainActor [weak self] in self?.finishTeardown() }
        }
        return finalized ?? transcription
    }

    /// Thread-safe completion flag for polling task completion.
    private final class CompletionFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false

        var isDone: Bool {
            lock.lock()
            defer { lock.unlock() }
            return done
        }

        func markDone() {
            lock.lock()
            done = true
            lock.unlock()
        }
    }

    /// Tears down remaining pipeline state after finalization, mirroring
    /// ``stop()``. Main actor so state mutations stay serialized with the
    /// rest of the service's lifecycle changes.
    @MainActor
    private func finishTeardown() {
        // Invalidate in-flight setup callbacks, then full teardown.
        generation += 1
        tearDownAudio()
        deactivateSession()
    }

    /// Waits (bounded) for analyzer setup to leave `.preparing`.
    private func waitForAnalyzerReadiness(timeout: Duration) async {
        let deadline = ContinuousClock.now + timeout
        while state == .preparing, ContinuousClock.now < deadline {
            try? await Task.sleep(for: Self.pollInterval)
            if Task.isCancelled { return }
        }
    }

    /// Waits for the feeder to drain the backlog and end the analyzer input,
    /// then finalizes through end-of-input so final results flush into
    /// `transcription`. Polls instead of awaiting task values so the enclosing
    /// timeout can cancel the wait.
    private func drainAndFinalize() async {
        await waitFor(analyzerTask)
        guard !Task.isCancelled else { return }
        if let analyzer {
            try? await analyzer.finalizeAndFinishThroughEndOfInput()
        }
        await waitFor(resultTask)
    }

    /// Returns when the task completes or the caller is cancelled. Polls a
    /// completion flag rather than awaiting `task.value`, which ignores
    /// cancellation and would stall the bounded wait in finish().
    private func waitFor(_ task: Task<Void, Never>?) async {
        guard let task else { return }
        let completion = CompletionFlag()
        let watcher = Task {
            await task.value
            completion.markDone()
        }
        defer { watcher.cancel() }
        while !completion.isDone {
            try? await Task.sleep(for: Self.pollInterval)
            if Task.isCancelled { return }
        }
    }

    func start() {
        guard case .idle = state else { return }
        generation += 1
        error = nil
        transcription = ""
        committedTranscription = ""
        hasReceivedTranscription = false
        state = .preparing

        let gen = generation
        Task { [weak self] in
            await self?.beginRecording(generation: gen)
        }
    }

    func stop() {
        generation += 1
        guard state != .idle else { return }

        tearDownAudio()
        deactivateSession()
    }

    /// Resets to `.idle` and releases the audio session (unless an external
    /// owner such as CallKit manages it).
    private func deactivateSession() {
        state = .idle

        if keepSessionActive { return }

        DispatchQueue.main.async { UIApplication.shared.isIdleTimerDisabled = false }
        DispatchQueue.global(qos: .utility).async {
            try? AVAudioSession.sharedInstance().setActive(
                false, options: .notifyOthersOnDeactivation
            )
        }
    }

    // MARK: - Private

    /// Stops the engine, cancels tasks, and tears down analyzer state.
    private func tearDownAudio() {
        stopObservingAudioNotifications()
        resultTask?.cancel()
        resultTask = nil
        analyzerTask?.cancel()
        analyzerTask = nil
        rawContinuation?.finish()
        rawContinuation = nil
        inputContinuation?.finish()
        inputContinuation = nil
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        analyzer = nil
        converter = nil
    }

    /// Sets up the audio pipeline in two phases:
    ///
    /// Phase A starts capturing immediately — audio session, tap, engine. Raw
    /// buffers back up in an unbounded stream while Phase B (transcriber and
    /// analyzer setup, the slow part) runs in parallel. Once the analyzer is
    /// up, the feeder drains the backlog from the true beginning of the
    /// utterance, so the first words are never lost.
    private func beginRecording(generation gen: Int, attempt: Int = 0) async {
        let engine = audioEngine
        let externalSessionOwner = keepSessionActive

        // --- Phase A — capture immediately ---

        // When keepSessionActive is true, an external owner (e.g. CallKit)
        // manages the audio session — skip setup to avoid conflicts.
        if !externalSessionOwner {
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(
                    .playAndRecord,
                    mode: .default,
                    options: [.allowBluetoothHFP, .defaultToSpeaker]
                )
                try session.setActive(true, options: .notifyOthersOnDeactivation)
            } catch {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    guard gen == generation else { return }
                    state = .error("Could not configure audio session.")
                }
                return
            }
        }

        // Always reset to clean state.
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        engine.reset()

        // The raw stream must exist before the tap is installed so capture
        // can start before the analyzer does. Unbounded because the backlog
        // it holds spans only analyzer setup (~hundreds of ms of PCM).
        var rawContinuation: AsyncStream<AVAudioPCMBuffer>.Continuation?
        let rawStream = AsyncStream<AVAudioPCMBuffer>(bufferingPolicy: .unbounded) {
            rawContinuation = $0
        }
        self.rawContinuation = rawContinuation

        do {
            try startCapture(
                engine: engine,
                rawContinuation: rawContinuation!
            )
        } catch {
            rawContinuation?.finish()
            self.rawContinuation = nil
            await retryCapture(
                generation: gen,
                attempt: attempt,
                message: "Could not start audio engine."
            )
            return
        }

        // Audio is flowing. If this attempt is already stale, stop before
        // touching global state.
        guard gen == generation else {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
            self.rawContinuation?.finish()
            self.rawContinuation = nil
            return
        }

        await MainActor.run { UIApplication.shared.isIdleTimerDisabled = true }

        // --- Phase B — analyzer, in parallel with capture ---

        // Pick transcriber — prefer SpeechTranscriber on capable devices
        // with the locale's model already installed. Fall back to
        // DictationTranscriber rather than blocking on a download.
        // Use supportedLocale(equivalentTo:) to get the canonical locale
        // the framework recognizes (e.g. "da" → "da-DK"), and use THAT
        // for the installed check and transcriber init.
        let resolvedSpeechLocale: Locale? = await {
            guard SpeechTranscriber.isAvailable else { return nil }
            guard let canonical = await SpeechTranscriber.supportedLocale(
                equivalentTo: self.locale
            ) else { return nil }
            let installed = await SpeechTranscriber.installedLocales
            guard installed.contains(where: {
                $0.identifier(.bcp47) == canonical.identifier(.bcp47)
            }) else {
                // Kick off background download so it's ready next session.
                let transcriber = SpeechTranscriber(
                    locale: canonical,
                    transcriptionOptions: [],
                    reportingOptions: [.volatileResults, .fastResults],
                    attributeOptions: []
                )
                Task.detached(priority: .utility) {
                    do {
                        if let request = try await AssetInventory.assetInstallationRequest(
                            supporting: [transcriber]
                        ) {
                            try await request.downloadAndInstall()
                            AppLogger
                                .info(
                                    "SpeechTranscriber model for \(public: canonical.identifier(.bcp47)) installed"
                                )
                        }
                    } catch {
                        // Model may not be available yet — that's fine.
                    }
                }
                return nil
            }
            return canonical
        }()

        let speechTranscriber: SpeechTranscriber?
        let dictTranscriber: DictationTranscriber?

        if let speechLocale = resolvedSpeechLocale {
            speechTranscriber = SpeechTranscriber(
                locale: speechLocale,
                transcriptionOptions: [],
                reportingOptions: [.volatileResults, .fastResults],
                attributeOptions: []
            )
            dictTranscriber = nil
            AppLogger.info("Using SpeechTranscriber for \(public: speechLocale.identifier(.bcp47))")
        } else {
            speechTranscriber = nil
            dictTranscriber = DictationTranscriber(
                locale: locale, preset: .progressiveLongDictation
            )
            AppLogger.info("Using DictationTranscriber for \(public: locale.identifier(.bcp47))")
        }

        // Build module list for the analyzer
        let modules: [any SpeechModule] =
            if let st = speechTranscriber {
                [st]
            } else {
                [dictTranscriber!]
            }

        // Create analyzer (Apple pattern: create first, start later).
        let newAnalyzer = SpeechAnalyzer(modules: modules)

        // Bias recognition toward the user's vocabulary: set the context before
        // start so buffered audio from the first moment sees it.
        do {
            try await newAnalyzer.setContext(makeAnalysisContext())
        } catch {
            AppLogger.warning(
                "Failed to set speech analysis context: \(private: error.localizedDescription)",
                category: .general
            )
        }

        // Get the format the analyzer expects.
        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: modules
        ) else {
            await abortAnalyzerSetup(
                engine: engine,
                message: "No compatible audio format available.",
                generation: gen
            )
            return
        }

        // The analyzer input stream; the raw stream already exists and is
        // collecting audio from the live tap.
        let (inputSequence, inputBuilder) = AsyncStream<AnalyzerInput>.makeStream()

        // Store state before starting the analyzer.
        analyzer = newAnalyzer
        inputContinuation = inputBuilder
        converter = BufferConverter()

        // Step 1: Create result iteration task BEFORE calling start()
        // (Apple's pattern — results task must be running when start begins).
        let currentGen = gen
        if let st = speechTranscriber {
            resultTask = Task { [weak self] in
                await self?.iterateResults(st.results, generation: currentGen)
            }
        } else if let dt = dictTranscriber {
            resultTask = Task { [weak self] in
                await self?.iterateResults(dt.results, generation: currentGen)
            }
        }

        // Step 2: Call start(inputSequence:).
        let capturedConverter = converter!
        let capturedAnalyzerFormat = analyzerFormat
        analyzerTask = Task {
            do {
                try await newAnalyzer.start(inputSequence: inputSequence)
            } catch {
                guard !Task.isCancelled else { return }
                AppLogger.error("Analyzer start failed: \(public: error.localizedDescription)")
            }
        }

        // Step 3: Feeder task — bridges raw audio from tap to analyzer.
        // Runs on the cooperative pool (not the real-time audio thread),
        // matching Apple's `for await input in audioStream()` pattern.
        let feederTask = Task {
            for await buffer in rawStream {
                do {
                    let converted = try capturedConverter.convert(
                        buffer, to: capturedAnalyzerFormat
                    )
                    inputBuilder.yield(AnalyzerInput(buffer: converted))
                } catch {}
            }
            inputBuilder.finish()
        }
        let originalAnalyzerTask = analyzerTask
        analyzerTask = Task {
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await originalAnalyzerTask?.value }
                group.addTask { await feederTask.value }
                for await _ in group {}
            }
        }

        // Capture may already be running — tear down the analyzer side and
        // the capture that belongs to this (stale or failed) attempt.
        guard gen == generation else {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
            analyzer = nil
            inputContinuation = nil
            self.rawContinuation?.finish()
            self.rawContinuation = nil
            resultTask?.cancel()
            resultTask = nil
            analyzerTask?.cancel()
            analyzerTask = nil
            return
        }

        await MainActor.run { [weak self] in
            guard let self else { return }
            guard gen == generation else { return }
            state = .listening
            // In live-call mode an external AudioRouteCoordinator owns route
            // recovery; only self-observe during standalone dictation.
            if !keepSessionActive {
                startObservingAudioNotifications()
            }
        }
    }

    /// Installs the input tap and starts the engine so buffers flow into
    /// `rawContinuation` immediately. Throws if either step fails.
    private func startCapture(
        engine: AVAudioEngine,
        rawContinuation: AsyncStream<AVAudioPCMBuffer>.Continuation
    ) throws {
        try ObjCExceptionCatcher.try {
            engine.inputNode.installTap(
                onBus: 0, bufferSize: 4096,
                format: authoritativeInputFormat(engine: engine)
            ) { buffer, _ in
                rawContinuation.yield(buffer)
            }
        }
        engine.prepare()
        try engine.start()
    }

    /// Retries capture setup with backoff, or surfaces an error when the
    /// retry budget is exhausted.
    private func retryCapture(generation gen: Int, attempt: Int, message: String) async {
        let maxRetries = 8
        if attempt < maxRetries {
            let delay = min(1.0, 0.3 + Double(attempt) * 0.2)
            try? await Task.sleep(for: .milliseconds(Int(delay * 1000)))
            guard gen == generation else { return }
            await beginRecording(generation: gen, attempt: attempt + 1)
        } else {
            await MainActor.run { [weak self] in
                guard let self else { return }
                guard gen == generation else { return }
                state = .error(message)
            }
        }
    }

    /// Tears down a failed analyzer setup, including the capture that has
    /// already started for this attempt.
    private func abortAnalyzerSetup(
        engine: AVAudioEngine,
        message: String,
        generation gen: Int
    ) async {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        analyzer = nil
        inputContinuation = nil
        rawContinuation?.finish()
        rawContinuation = nil
        resultTask?.cancel()
        resultTask = nil
        analyzerTask?.cancel()
        analyzerTask = nil

        await MainActor.run { [weak self] in
            guard let self else { return }
            guard gen == generation else { return }
            state = .error(message)
        }
    }

    /// Consumes an async sequence of transcription results, updating
    /// `transcription` with partial and final results.
    private func iterateResults<S: AsyncSequence>(
        _ results: S,
        generation gen: Int
    ) async where S.Element: TranscriberResult {
        do {
            for try await result in results {
                guard !Task.isCancelled else { return }
                let text = String(result.text.characters)
                let isFinal = result.isFinal
                await MainActor.run { [weak self] in
                    guard let self, gen == generation else { return }
                    let committed = committedTranscription
                    transcription = committed.isEmpty ? text : committed + " " + text
                    if !hasReceivedTranscription, !text.isEmpty {
                        hasReceivedTranscription = true
                        state = .transcribing
                    }
                    if isFinal {
                        committedTranscription = transcription
                    }
                }
            }
        } catch {
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self, gen == generation else { return }
                if transcription.isEmpty {
                    state = .error("Speech recognition failed.")
                    stop()
                }
            }
        }
    }

    // MARK: - Audio Notification Observers

    private func startObservingAudioNotifications() {
        stopObservingAudioNotifications()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleEngineConfigChange),
            name: .AVAudioEngineConfigurationChange,
            object: audioEngine
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioInterruption),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
    }

    private func stopObservingAudioNotifications() {
        NotificationCenter.default.removeObserver(
            self, name: .AVAudioEngineConfigurationChange, object: audioEngine
        )
        NotificationCenter.default.removeObserver(
            self, name: AVAudioSession.interruptionNotification, object: nil
        )
    }

    /// Called by the system when the audio hardware configuration changes
    /// (e.g. speaker → Bluetooth). Hops to the main actor so recovery is
    /// serialized and never races a concurrent restart.
    @objc private func handleEngineConfigChange(_ notification: Notification) {
        Task { @MainActor [weak self] in self?.recover() }
    }

    /// Called when car BT or another app claims the audio session. Hops to the
    /// main actor so state transitions stay serialized and on-actor.
    @objc private func handleAudioInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else { return }

        switch type {
        case .began:
            Task { @MainActor [weak self] in
                guard let self, isRecording else { return }
                tearDownAudio()
                generation += 1
                committedTranscription = transcription
                state = .preparing
            }

        case .ended:
            let shouldResume =
                (userInfo[AVAudioSessionInterruptionOptionKey] as? UInt).map {
                    AVAudioSession.InterruptionOptions(rawValue: $0).contains(.shouldResume)
                } ?? false
            Task { @MainActor [weak self] in
                guard let self, isRecovering else { return }
                if !shouldResume {
                    try? await Task.sleep(for: .milliseconds(500))
                }
                guard isRecovering else { return }
                await beginRecording(generation: generation)
            }

        @unknown default:
            break
        }
    }
}

/// Preview stub — all no-ops.
struct PreviewDictationService: DictationService {
    var state: AppDictationState {
        .idle
    }

    var transcription: String {
        ""
    }

    var error: String? {
        nil
    }

    func start() {}
    func stop() {}
    func finish() async -> String {
        ""
    }

    func setLocale(_ locale: Locale) {}
    func setContextualStrings(_ strings: [String]) {}
}
