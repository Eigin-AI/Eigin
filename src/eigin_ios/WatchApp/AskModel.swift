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
    private let session = PhoneSession()

    init() {
        session.onAnswer = { [weak self] _, errorMessage in
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
        session.send(url: url) { [weak self] message in
            self?.fail(message)
        }
        // The reply itself arrives as a wrist notification.
        WKInterfaceDevice.current().play(.click)
    }

    /// The turn finished ... completion is a haptic and a fresh start. A
    /// newer ask owns the watch, so a stale turn's completion stays silent.
    private func turnFinished(errorMessage: String?) {
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
