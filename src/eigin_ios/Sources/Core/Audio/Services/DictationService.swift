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
        case .listening, .transcribing: true
        default: false
        }
    }
}

/// Both result types share `text` + `isFinal` but `text` is not on the
/// protocol. This small conformance lets us iterate results generically.
private protocol TranscriberResult {
    var text: AttributedString { get }
    var isFinal: Bool { get }
}

extension SpeechTranscriber.Result: TranscriberResult {}
extension DictationTranscriber.Result: TranscriberResult {}

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
    }

    var isRecovering: Bool {
        state == .preparing
    }

    var isRecording: Bool {
        state.isActive
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

    /// Sets up the audio session, engine, transcriber, and analyzer.
    /// Follows Apple's recommended pattern: create analyzer → create result
    /// task → call start(inputSequence:) → feed audio.
    private func beginRecording(generation gen: Int, attempt: Int = 0) async {
        let engine = audioEngine
        let externalSessionOwner = keepSessionActive

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

        // Get the format the analyzer expects.
        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: modules
        ) else {
            await MainActor.run { [weak self] in
                guard let self else { return }
                guard gen == generation else { return }
                state = .error("No compatible audio format available.")
            }
            return
        }

        // Create two streams matching Apple's sample pattern:
        // 1. Raw PCM buffers from the audio tap → async world
        // 2. Converted AnalyzerInput buffers → SpeechAnalyzer
        let (inputSequence, inputBuilder) = AsyncStream<AnalyzerInput>.makeStream()
        var rawContinuation: AsyncStream<AVAudioPCMBuffer>.Continuation?
        let rawStream = AsyncStream<AVAudioPCMBuffer>(bufferingPolicy: .unbounded) {
            rawContinuation = $0
        }

        // Store state before starting the engine.
        analyzer = newAnalyzer
        inputContinuation = inputBuilder
        self.rawContinuation = rawContinuation
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

        // Step 4: Install tap with native format — yields raw buffers
        // to the intermediate stream (not directly to the analyzer).
        let nativeFormat = authoritativeInputFormat(engine: engine)

        do {
            try ObjCExceptionCatcher.try {
                engine.inputNode.installTap(
                    onBus: 0, bufferSize: 4096,
                    format: nativeFormat
                ) { buffer, _ in
                    rawContinuation?.yield(buffer)
                }
            }
        } catch {
            analyzer = nil
            inputContinuation = nil
            self.rawContinuation?.finish()
            self.rawContinuation = nil
            converter = nil
            resultTask?.cancel()
            resultTask = nil
            analyzerTask?.cancel()
            analyzerTask = nil
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
                    state = .error("Could not start audio engine.")
                }
            }
            return
        }

        // Step 5: Start the engine — audio now flows.
        engine.prepare()
        do {
            try engine.start()
        } catch {
            engine.inputNode.removeTap(onBus: 0)
            analyzer = nil
            inputContinuation = nil
            self.rawContinuation?.finish()
            self.rawContinuation = nil
            converter = nil
            resultTask?.cancel()
            resultTask = nil
            analyzerTask?.cancel()
            analyzerTask = nil
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
                    state = .error("Could not start audio engine.")
                }
            }
            return
        }

        // Check generation before committing.
        guard gen == generation else {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
            analyzer = nil
            inputContinuation = nil
            self.rawContinuation?.finish()
            self.rawContinuation = nil
            converter = nil
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
            UIApplication.shared.isIdleTimerDisabled = true
            startObservingAudioNotifications()
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
    /// (e.g. speaker → Bluetooth). Tears down and restarts.
    @objc private func handleEngineConfigChange(_ notification: Notification) {
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

    /// Called when car BT or another app claims the audio session.
    @objc private func handleAudioInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else { return }

        switch type {
        case .began:
            guard isRecording else { return }
            tearDownAudio()
            generation += 1
            committedTranscription = transcription
            state = .preparing

        case .ended:
            guard isRecovering else { return }
            let delay: TimeInterval = {
                if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt,
                   AVAudioSession.InterruptionOptions(rawValue: optionsValue).contains(
                       .shouldResume
                   )
                {
                    return 0
                }
                return 0.5
            }()
            let gen = generation
            Task { [weak self] in
                if delay > 0 {
                    try? await Task.sleep(for: .milliseconds(Int(delay * 1000)))
                }
                guard let self, isRecovering else { return }
                await beginRecording(generation: gen)
            }

        @unknown default:
            break
        }
    }
}

// MARK: - Buffer Converter

/// Converts audio buffers between formats. Matches the pattern from
/// Apple's SpeechAnalyzer sample code.
private final class BufferConverter: @unchecked Sendable {
    private var converter: AVAudioConverter?
    private var currentInputFormat: AVAudioFormat?

    func convert(_ buffer: AVAudioPCMBuffer, to outputFormat: AVAudioFormat) throws
        -> AVAudioPCMBuffer
    {
        let inputFormat = buffer.format

        // Recreate the converter if the input format changed (e.g. route change).
        if converter == nil || currentInputFormat != inputFormat {
            converter = AVAudioConverter(from: inputFormat, to: outputFormat)
            currentInputFormat = inputFormat
        }

        guard let converter else {
            throw NSError(
                domain: "DictationService", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Could not create audio converter"]
            )
        }

        let ratio = outputFormat.sampleRate / inputFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
        guard capacity > 0,
              let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity)
        else {
            throw NSError(
                domain: "DictationService", code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Could not create output buffer"]
            )
        }

        // Reset converter state before each conversion — without this,
        // the .endOfStream from a previous call permanently marks the
        // converter as "done" and subsequent conversions return 0 frames.
        converter.reset()

        var error: NSError?
        nonisolated(unsafe) var hasProvided = false
        converter.convert(to: output, error: &error) { _, outStatus in
            if hasProvided {
                outStatus.pointee = .endOfStream
                return nil
            }
            hasProvided = true
            outStatus.pointee = .haveData
            return buffer
        }

        if let error { throw error }
        return output
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
    func setLocale(_ locale: Locale) {}
    func setContextualStrings(_ strings: [String]) {}
}
