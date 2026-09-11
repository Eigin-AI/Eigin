#if DEBUG || EIGIN_DEV
import Foundation

/// A fake SpeechSynthesizing implementation for testing DefaultSpeechService
/// without touching AVFoundation.
@MainActor
final class FakeSpeechSynthesizer: SpeechSynthesizing {
    var onFinish: ((_ text: String) -> Void)?
    var onCancel: ((_ text: String) -> Void)?
    var onWillSpeak: ((_ range: NSRange, _ text: String) -> Void)?

    /// All texts passed to `speak`, in order.
    private(set) var spokenTexts: [String] = []
    /// Number of times `stopSpeaking` was called.
    private(set) var stopCount = 0

    func speak(_ text: String) {
        spokenTexts.append(text)
    }

    func finishSpeaking() {}

    func stopSpeaking() {
        stopCount += 1
    }

    // MARK: - Test Helpers

    /// Simulate an utterance finishing playback.
    func simulateFinish(_ text: String) {
        onFinish?(text)
    }

    /// Simulate an utterance being cancelled.
    func simulateCancel(_ text: String) {
        onCancel?(text)
    }
}
#endif
