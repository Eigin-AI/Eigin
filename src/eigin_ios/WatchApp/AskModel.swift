import Foundation
import Observation
import WatchKit

/// The watch companion's state machine: ready → listening → sending, and
/// back. Fire-and-forget — the phone answers by notification, so the watch's
/// only job is to record a question, send it reliably, and feel the
/// completion.
@Observable
@MainActor
final class AskModel {
    enum Phase: Equatable {
        case ready
        case listening
        case sending
    }

    private(set) var phase: Phase = .ready
    /// Set when something failed; replaces the prompt line in the ready state.
    private(set) var error: String?

    /// Anchors the blob's choreography seed.
    let shownAt = Date.now
    /// The listening pulse, ramped in and out — so the blob eases into and
    /// out of moving instead of jumping.
    private(set) var pulse = MorphIntensity.none

    private let recorder = VoiceRecorder()
    private let link = PhoneLink()

    /// How long to wait before assuming the phone is silent — long enough
    /// for the phone's ~30s background budget plus transfer and transcription
    /// slack.
    private let slowTurnTimeout: TimeInterval
    private var slowTurnTask: Task<Void, Never>?

    /// `slowTurnTimeout` is injectable to keep the behaviour easily exercisable
    /// in a future watch test target; the real watch uses the default.
    init(slowTurnTimeout: TimeInterval = 45) {
        self.slowTurnTimeout = slowTurnTimeout
        link.onAnswer = { [weak self] _, errorMessage in
            self?.turnFinished(errorMessage: errorMessage)
        }
    }

    /// The press that starts the push-to-talk recording.
    func pressBegan() {
        guard phase == .ready else { return }
        error = nil
        phase = .listening
        pulse = pulse.transitioned(to: true, at: .now)
        WKInterfaceDevice.current().play(.start)
        recorder.start { [weak self] outcome in
            self?.recordingEnded(outcome)
        }
    }

    /// The release that sends. A press with nothing said discards quietly.
    func pressEnded() {
        guard phase == .listening else { return }
        recorder.stop()
    }

    /// The watch left the foreground — the wrist dropped and the system
    /// cancelled a press mid-hold. That still means "done talking": send
    /// what was said, eagerly, without waiting for a suspension-stranded
    /// delegate callback.
    func handleDismissal() {
        guard phase == .listening, let url = recorder.flush() else { return }
        sendRecording(url)
    }

    // MARK: - Transitions

    private func recordingEnded(_ outcome: VoiceRecorder.Outcome) {
        switch outcome {
        case .recorded(let url):
            sendRecording(url)
        case .silent:
            settle()
        case .failed:
            fail(Localized.Watch.cantRecord)
        }
    }

    private func sendRecording(_ url: URL) {
        phase = .sending
        link.send(url: url) { [weak self] message in
            self?.fail(message)
        }
        scheduleSlowTurnTimeout()
        // The reply itself arrives as a wrist notification.
        WKInterfaceDevice.current().play(.click)
    }

    /// Backstop for a phone that never answers at all — force-quit, crash,
    /// never launched — where even the phone's own give-up message cannot
    /// arrive.
    private func scheduleSlowTurnTimeout() {
        slowTurnTask?.cancel()
        slowTurnTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(slowTurnTimeout))
            guard !Task.isCancelled else { return }
            slowTurn()
        }
    }

    /// The turn outstayed its welcome: settle back to ready with a word
    /// about giving up and how to continue instead of a forever-spinner.
    /// The phone-side give-up usually lands first, at ~30s.
    private func slowTurn() {
        guard phase == .sending else { return }
        fail(Localized.Watch.turnDelayed)
    }

    /// The turn finished ... completion is a haptic and a fresh start. A
    /// newer ask owns the watch, so a stale turn's completion stays silent.
    private func turnFinished(errorMessage: String?) {
        slowTurnTask?.cancel()
        guard phase == .sending else { return }
        if let errorMessage {
            fail(errorMessage)
            return
        }
        WKInterfaceDevice.current().play(.notification)
        settle()
    }

    private func fail(_ message: String) {
        WKInterfaceDevice.current().play(.failure)
        settle()
        error = message
    }

    /// Back to stillness — the pulse ramps out wherever it was mid-flight.
    private func settle() {
        pulse = pulse.transitioned(to: false, at: .now)
    }
}
