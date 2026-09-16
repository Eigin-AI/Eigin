import AVFoundation
import Foundation
import Observation

/// Records a spoken question on the watch for as long as the wearer holds
/// the screen down. Push-to-talk: the press is the whole protocol — no silence
/// detection to misjudge, because a deliberate hold and a deliberate release
/// say everything. The only judgment left here is whether anyone actually
/// spoke, so a stray press discards instead of sending silence to the phone.
@Observable
@MainActor
final class VoiceRecorder: NSObject {
    /// What a finished recording turned out to be.
    enum Outcome {
        /// A question was captured — send it.
        case recorded(URL)
        /// Pressed, released, nothing said — back to ready, nothing to send.
        case silent
        /// Recording failed or microphone access is off.
        case failed
    }

    /// A deliberate hold can run long, so the cap is generous — a backstop
    /// against a pocketed press, not a turn limit.
    private static let maxDuration: TimeInterval = 60
    /// Loudest reading this recording must have produced for "someone spoke".
    private static let speechFloor: Float = -35

    private(set) var isRecording = false

    private var recorder: AVAudioRecorder?
    private var meterTask: Task<Void, Never>?
    private var startedAt: Date?
    private var onFinish: ((Outcome) -> Void)?
    /// Loudness of this recording so far; decides recorded vs silent.
    private var maxLevel: Float = -160
    /// Whether the caller still wants the recording started. Cleared by a
    /// release that lands while the microphone permission is still pending —
    /// otherwise the grant would begin recording after the press ended.
    private var wantsRecording = false

    /// Starts recording, calling `onFinish` with the outcome when it stops.
    func start(onFinish: @escaping (Outcome) -> Void) {
        guard !isRecording else { return }
        self.onFinish = onFinish
        wantsRecording = true

        AVAudioApplication.requestRecordPermission { [weak self] granted in
            Task { @MainActor in
                guard let self else { return }
                guard granted else {
                    self.finish(.failed)
                    return
                }
                // The press may have ended while the system prompt was up.
                guard self.wantsRecording else {
                    self.finish(.silent)
                    return
                }
                self.beginRecording()
            }
        }
    }

    /// Stops early — the release of a push-to-talk press.
    func stop() {
        wantsRecording = false
        guard isRecording, let recorder else { return }
        recorder.stop()
    }

    /// Stops immediately and returns the recording synchronously, without
    /// waiting for the delegate. The wrist-down flush runs while the app is
    /// being suspended — the async delegate callback can be stranded until
    /// the app is next opened, which defers the send behind the next ask.
    func flush() -> URL? {
        guard isRecording, let current = recorder else { return nil }
        wantsRecording = false
        let url = current.url
        meterTask?.cancel()
        meterTask = nil
        isRecording = false
        current.delegate = nil
        current.stop()
        recorder = nil
        startedAt = nil
        onFinish = nil
        maxLevel = -160
        return url
    }

    private func beginRecording() {
        let session = AVAudioSession.sharedInstance()
        // Voice mode engages Apple's voice processing — the high-pass that
        // cuts rumble and wind, plus level control that keeps the power
        // meter meaningful for the spoke check.
        try? session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth])
        session.activate(options: []) { [weak self] activated, _ in
            Task { @MainActor in
                guard let self else { return }
                guard activated else {
                    self.finish(.failed)
                    return
                }
                self.openRecorder()
            }
        }
    }

    private func openRecorder() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("watch-question-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 22050.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]

        guard let recorder = try? AVAudioRecorder(url: url, settings: settings) else {
            finish(.failed)
            return
        }
        recorder.delegate = self
        recorder.isMeteringEnabled = true
        guard recorder.record() else {
            finish(.failed)
            return
        }

        self.recorder = recorder
        isRecording = true
        startedAt = .now
        maxLevel = -160
        watchLevels()
    }

    /// A light poll: the loudest thing heard (the spoke check), and the cap.
    private func watchLevels() {
        meterTask?.cancel()
        meterTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard let self, let recorder, isRecording else { return }

                recorder.updateMeters()
                maxLevel = max(maxLevel, recorder.averagePower(forChannel: 0))

                if let startedAt,
                   Date.now.timeIntervalSince(startedAt) >= Self.maxDuration
                {
                    recorder.stop()
                }
            }
        }
    }

    private func finish(_ outcome: Outcome) {
        meterTask?.cancel()
        meterTask = nil
        isRecording = false
        recorder = nil
        startedAt = nil
        maxLevel = -160
        let callback = onFinish
        onFinish = nil
        callback?(outcome)
    }

    /// Completes after a delegate stop: the recording itself decides whether
    /// anyone spoke.
    private func completed(successfully: Bool, url: URL) {
        if !successfully {
            finish(.failed)
        } else if maxLevel >= Self.speechFloor {
            finish(.recorded(url))
        } else {
            finish(.silent)
        }
    }
}

extension VoiceRecorder: AVAudioRecorderDelegate {
    nonisolated func audioRecorderDidFinishRecording(
        _ recorder: AVAudioRecorder, successfully flag: Bool
    ) {
        let url = recorder.url
        Task { @MainActor [weak self] in
            self?.completed(successfully: flag, url: url)
        }
    }
}
