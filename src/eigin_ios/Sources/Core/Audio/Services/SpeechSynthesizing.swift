@preconcurrency import AVFoundation

// MARK: - SpeechSynthesizing Protocol

/// Minimal abstraction over speech synthesis for testability.
///
/// Voice configuration is handled at construction time, not per-call.
/// Each engine (system, Kokoro, etc.) resolves its own voice representation.
@MainActor
protocol SpeechSynthesizing: AnyObject {
    /// Called when an utterance finishes speaking. Parameter is the spoken text.
    var onFinish: ((_ text: String) -> Void)? { get set }
    /// Called when an utterance is cancelled. Parameter is the text.
    var onCancel: ((_ text: String) -> Void)? { get set }
    /// Called as the synthesizer progresses through an utterance.
    var onWillSpeak: ((_ range: NSRange, _ text: String) -> Void)? { get set }

    func speak(_ text: String)
    /// Signal that no more text will be enqueued via `speak()`.
    /// Engines that batch generation (e.g. PocketTTS sessions) use this
    /// to flush remaining audio and fire final completion callbacks.
    func finishSpeaking()
    func stopSpeaking()
}

// MARK: - System Implementation

/// Production implementation wrapping `AVSpeechSynthesizer`.
///
/// Voice is resolved once at construction. Pass a ``SpeechVoice`` to
/// select a specific system voice, or `nil` to use the language default.
@MainActor
final class SystemSpeechSynthesizer: NSObject, SpeechSynthesizing, @unchecked Sendable {
    var onFinish: ((_ text: String) -> Void)?
    var onCancel: ((_ text: String) -> Void)?
    var onWillSpeak: ((_ range: NSRange, _ text: String) -> Void)?

    private let synthesizer = AVSpeechSynthesizer()
    private let resolvedVoice: AVSpeechSynthesisVoice?

    init(voice: SpeechVoice? = nil, language: AppLanguage = LanguageManager().currentLanguage) {
        if let voiceID = voice?.identifier, !voiceID.isEmpty,
           let avVoice = AVSpeechSynthesisVoice(identifier: voiceID),
           avVoice.language.hasPrefix(language.voiceLanguagePrefix)
        {
            resolvedVoice = avVoice
        } else {
            resolvedVoice = AVSpeechSynthesisVoice(language: language.speechLocaleIdentifier)
        }
        super.init()
        synthesizer.delegate = self
    }

    func finishSpeaking() {}

    func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = resolvedVoice
        synthesizer.speak(utterance)
    }

    func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}

extension SystemSpeechSynthesizer: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        willSpeakRangeOfSpeechString characterRange: NSRange,
        utterance: AVSpeechUtterance
    ) {
        let text = utterance.speechString
        Task { @MainActor in
            self.onWillSpeak?(characterRange, text)
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        let text = utterance.speechString
        Task { @MainActor in
            self.onFinish?(text)
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        let text = utterance.speechString
        Task { @MainActor in
            self.onCancel?(text)
        }
    }
}
