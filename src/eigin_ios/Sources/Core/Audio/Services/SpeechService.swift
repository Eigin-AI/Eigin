@preconcurrency import AVFoundation
import Observation
import UIKit

/// Text-to-speech playback service.
@MainActor
protocol SpeechService {
    var isSpeaking: Bool { get }
    /// True while the active TTS engine is loading its model into memory.
    var isPreparingEngine: Bool { get }
    /// True after speech is requested but before the first audio frame starts playing.
    var isBuffering: Bool { get }
    /// The original (pre-sanitized) text currently being spoken, or nil (one-shot mode).
    var currentText: String? { get }
    /// The voice identifier to use. Set this from the agent's voice preference.
    var voiceIdentifier: String? { get set }
    /// Text spoken so far, updated progressively.
    var speakingText: String { get }
    /// Called when all speech completes.
    var onComplete: (() -> Void)? { get set }
    /// Called when the first audio frame begins playing after a speech request.
    var onAudioStarted: (() -> Void)? { get set }

    func speak(_ text: String)
    func stop()

    // Streaming
    func feedDelta(_ delta: String)
    func finish()
    func cancel()
    func reset()
}

/// Unified speech service handling both one-shot and streaming TTS.
///
/// - **One-shot** (`speak`/`stop`): Used by chat message views for reading messages aloud.
/// - **Streaming** (`feedDelta`/`finish`/`cancel`/`reset`): Used by ``LiveCallService``
///   for turn-based voice conversations with sentence-boundary queueing.
///
/// Both modes share the same ``SpeechSynthesizing`` backend and observable state.
@Observable
@MainActor
final class DefaultSpeechService: SpeechService, @unchecked Sendable {
    // MARK: - Observable State

    /// The text spoken so far, updated word-by-word via synthesizer callbacks.
    /// In one-shot mode this tracks progress through the single utterance.
    /// In streaming mode this accumulates across sentences.
    private(set) var speakingText = ""

    /// Whether any utterance is currently playing.
    private(set) var isSpeaking = false

    /// True while the active TTS engine is loading its model into memory.
    var isPreparingEngine: Bool {
        resolver.bestReadyProvider(for: LanguageManager().currentLanguage).isLoadingEngine
    }

    /// True after speech is requested but before the first audio frame starts playing.
    var isBuffering: Bool {
        isSpeaking && !hasAudioStarted
    }

    /// The original (pre-sanitized) text passed to `speak()`, or nil in streaming mode.
    private(set) var currentText: String?

    /// Set to true when the first `onWillSpeak` fires; reset when speech is requested.
    private(set) var hasAudioStarted = false

    /// Called when all utterances complete after the stream finishes (streaming mode),
    /// or when the single utterance finishes (one-shot mode).
    var onComplete: (() -> Void)?

    /// Called when the first audio frame begins playing after a speech request.
    var onAudioStarted: (() -> Void)?

    // MARK: - Private State

    private var synthesizer: any SpeechSynthesizing
    private var pendingUtterances = 0
    private var contentBuffer = ""
    private var spokenOffset = 0
    private var streamFinished = false
    private var spokenPrefix = ""
    /// FIFO queue mapping sanitized → original text for progress tracking.
    /// Using an ordered array avoids key collisions when the same sentence
    /// appears twice in a turn (a plain dictionary would overwrite the first entry).
    private var utteranceQueue: [(sanitized: String, original: String)] = []
    /// Tracks whether we're in one-shot mode (for audio session / idle timer management).
    private var isOneShotMode = false

    /// Resolver for automatic engine selection. Picks the best TTS engine
    /// based on language, device capability, and model availability.
    let resolver: SpeechEngineResolver

    /// The voice identifier to use. Set this from the current agent's voice preference.
    /// The service automatically resolves the right engine and synthesizer.
    var voiceIdentifier: String?

    /// Tracks the last resolved voice+engine to avoid recreating the synthesizer unnecessarily.
    private var resolvedVoiceID: String?
    private var resolvedEngineKind: SpeechEngineKind?

    // MARK: - Init

    init(resolver: SpeechEngineResolver, synthesizer: (any SpeechSynthesizing)? = nil) {
        self.resolver = resolver
        self.synthesizer = synthesizer ?? SystemSpeechSynthesizer()
        // When a synthesizer is explicitly injected (e.g. in tests), mark the engine
        // as already resolved so refreshSynthesizerIfNeeded won't replace it.
        if synthesizer != nil {
            let language = LanguageManager().currentLanguage
            resolvedEngineKind = resolver.bestReadyProvider(for: language).engineKind
        }
        wireCallbacks()
    }

    // MARK: - Engine Management

    /// Replace the underlying synthesizer. Called internally by `refreshSynthesizerIfNeeded`.
    private func setSynthesizer(_ newSynthesizer: any SpeechSynthesizing) {
        synthesizer.stopSpeaking()
        synthesizer = newSynthesizer
        resolvedVoiceID = nil
        resolvedEngineKind = nil
        wireCallbacks()
    }

    // MARK: - One-Shot API

    /// Speak text in one shot (chat bubble playback).
    /// Sanitizes markdown, manages audio session and idle timer.
    /// If a ``resolver`` is set, automatically picks the best engine.
    func speak(_ text: String) {
        // Stop any in-progress playback before starting new one.
        synthesizer.stopSpeaking()
        refreshSynthesizerIfNeeded()
        isOneShotMode = true
        currentText = text
        isSpeaking = true
        hasAudioStarted = false
        speakingText = ""
        spokenPrefix = ""
        streamFinished = false
        pendingUtterances = 0
        contentBuffer = ""
        spokenOffset = 0
        utteranceQueue.removeAll()

        DispatchQueue.main.async { UIApplication.shared.isIdleTimerDisabled = true }

        // Set up audio session for chat playback. During live calls,
        // CallKit owns the session — only streaming mode is used there.
        try? AVAudioSession.sharedInstance().setCategory(
            .playback, mode: .default, options: [.allowBluetoothHFP]
        )
        try? AVAudioSession.sharedInstance().setActive(true)

        synthesizer.stopSpeaking()

        let sanitized = Self.sanitizeForSpeech(text)
        guard !sanitized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            finishOneShot()
            return
        }

        // Split per the active engine's one-shot chunking strategy.
        let strategy = currentChunkingStrategy.oneShot
        let utterances =
            sanitized
                .components(separatedBy: "\n\n")
                .flatMap { $0.chunked(by: strategy) }
                .filter { !$0.isEmpty }

        streamFinished = true
        for utterance in utterances {
            pendingUtterances += 1
            synthesizer.speak(utterance)
        }
        synthesizer.finishSpeaking()
    }

    /// The active engine's preferred chunking strategy. Re-queried on each
    /// access so a mid-turn voice change picks up the new engine's preference
    /// (matching the existing `refreshSynthesizerIfNeeded` pattern).
    private var currentChunkingStrategy: SpeechChunkingStrategy {
        let language = LanguageManager().currentLanguage
        return resolver.bestReadyProvider(for: language).chunkingStrategy
    }

    /// Stop one-shot playback immediately.
    func stop() {
        synthesizer.stopSpeaking()
        finishOneShot()
    }

    // MARK: - Streaming API

    /// Append a delta from the LLM stream. Text accumulates until a sentence
    /// or paragraph boundary is reached, then schedules speech.
    func feedDelta(_ delta: String) {
        isOneShotMode = false
        if !isSpeaking { hasAudioStarted = false }
        isSpeaking = true
        contentBuffer += delta
        tryScheduleBuffered()
    }

    /// Flush all remaining text and begin speaking. Fires `onComplete`
    /// when the last utterance finishes (or immediately if nothing queued).
    func finish() {
        streamFinished = true

        let remaining = String(contentBuffer.dropFirst(spokenOffset))
        let trimmed = remaining.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            queueUtterance(trimmed)
            spokenOffset = contentBuffer.count
        }

        synthesizer.finishSpeaking()

        if pendingUtterances == 0 {
            completeStreaming()
        }
    }

    /// Stop the synthesizer immediately, flush all state, and reject late callbacks.
    func cancel() {
        synthesizer.stopSpeaking()
        contentBuffer = ""
        spokenPrefix = ""
        spokenOffset = 0
        streamFinished = true
        pendingUtterances = 0
        speakingText = ""
        isSpeaking = false
        hasAudioStarted = false
        utteranceQueue.removeAll()
    }

    /// Zero all state for the next turn.
    func reset() {
        synthesizer.stopSpeaking()
        contentBuffer = ""
        speakingText = ""
        spokenPrefix = ""
        spokenOffset = 0
        streamFinished = false
        pendingUtterances = 0
        currentText = nil
        isOneShotMode = false
        hasAudioStarted = false
        utteranceQueue.removeAll()
    }

    /// Strips Markdown syntax and emojis, then normalizes numbers, currencies,
    /// times, units, and abbreviations into spoken form for the given language.
    nonisolated static func sanitizeForSpeech(
        _ markdown: String,
        language: AppLanguage = LanguageManager().currentLanguage
    ) -> String {
        // Strip header tags
        let preprocessed = markdown.replacing(/(?m)^#{1,6}\s+(.+)$/) { match in
            let heading = match.1
            let trimmed = heading.dropLast(0)
            if let last = trimmed.last, ".!?:".contains(last) {
                return "\(heading)\n\n"
            }
            return "\(heading).\n\n"
        }

        // Strip other markdown symbols
        var cleaned: String = if let attributed = try? AttributedString(
            markdown: preprocessed,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            String(attributed.characters)
        } else {
            preprocessed
        }

        // Strip list markers (- , * , •, 1. etc.) at the start of lines.
        cleaned = cleaned.replacing(/(?m)^[\t ]*[-*•]\s+/, with: "")
        cleaned = cleaned.replacing(/(?m)^[\t ]*\d+\.\s+/, with: "")

        // Strip emojis, arrows, and other symbol characters that TTS models try to pronounce.
        cleaned = String(
            cleaned.unicodeScalars.filter { scalar in
                !(scalar.properties.isEmoji && scalar.properties.isEmojiPresentation)
                    && !scalar.properties.isEmojiModifier
                    && scalar.properties.generalCategory != .otherSymbol
                    && scalar.properties.generalCategory != .mathSymbol
            }
        )

        // Replace dashes with commas for natural speech pauses.
        // Handle spaced dashes first to avoid double spaces.
        cleaned = cleaned.replacingOccurrences(of: " — ", with: ", ")
        cleaned = cleaned.replacingOccurrences(of: " – ", with: ", ")
        cleaned = cleaned.replacingOccurrences(of: "—", with: ", ")

        // Collapse single newlines into sentence boundaries so list items
        // and short lines flow as continuous prose instead of separate chunks.
        // First, temporarily protect paragraph breaks (\n\n+).
        cleaned = cleaned.replacingOccurrences(of: "\n\n", with: "\u{0000}")
        // Replace remaining single newlines: add a period if the line doesn't
        // already end with sentence punctuation, otherwise just a space.
        cleaned = cleaned.replacing(/([^\n])\n/) { match in
            let last = match.1
            let lastChar = last.last ?? " "
            if ".!?:;,".contains(lastChar) {
                return "\(last) "
            }
            return "\(last). "
        }
        // Restore paragraph breaks.
        cleaned = cleaned.replacingOccurrences(of: "\u{0000}", with: "\n\n")

        // Collapse runs of whitespace (except paragraph breaks) to a single space.
        cleaned = cleaned.replacing(/[^\S\n]+/, with: " ")

        // Normalize numbers, currencies, times, units, and abbreviations
        // into spoken words for the target language.
        let locale = SpokenTextLocale.forLanguage(language)
        cleaned = SpokenTextNormalizer.normalize(cleaned, locale: locale)

        return cleaned
    }

    // MARK: - Private

    private func wireCallbacks() {
        synthesizer.onFinish = { [weak self] sanitizedText in
            guard let self else { return }
            // Remove the first matching entry (FIFO) so duplicate sentences
            // are handled correctly without key collisions.
            let original: String
            if let idx = utteranceQueue.firstIndex(where: { $0.sanitized == sanitizedText }) {
                original = utteranceQueue[idx].original
                utteranceQueue.remove(at: idx)
            } else {
                original = sanitizedText
            }
            if spokenPrefix.isEmpty {
                spokenPrefix = original
            } else {
                spokenPrefix += " " + original
            }
            pendingUtterances -= 1

            if isOneShotMode {
                if pendingUtterances <= 0 {
                    finishOneShot()
                }
            } else if pendingUtterances <= 0, streamFinished {
                pendingUtterances = 0
                completeStreaming()
            }
        }

        synthesizer.onCancel = { [weak self] sanitizedText in
            guard let self else { return }
            if let idx = utteranceQueue.firstIndex(where: { $0.sanitized == sanitizedText }) {
                utteranceQueue.remove(at: idx)
            }
            pendingUtterances = max(0, pendingUtterances - 1)
        }

        synthesizer.onWillSpeak = { [weak self] range, sanitizedText in
            guard let self else { return }
            if !hasAudioStarted {
                hasAudioStarted = true
                onAudioStarted?()
            }
            // Display the sanitized text — that's what's actually being spoken.
            // The original (pre-sanitization) text may contain markdown that
            // would be visible to the user if displayed directly.
            let progress =
                Double(min(range.upperBound, sanitizedText.count))
                    / Double(max(sanitizedText.count, 1))
            let rawChars = min(Int(progress * Double(sanitizedText.count)), sanitizedText.count)
            // Extend to the next word boundary so we never display a partial word.
            let endIndex: String.Index
            if rawChars >= sanitizedText.count {
                endIndex = sanitizedText.endIndex
            } else {
                let rawIdx = sanitizedText.index(sanitizedText.startIndex, offsetBy: rawChars)
                // Walk forward to end of current word (past any non-whitespace).
                endIndex =
                    sanitizedText[rawIdx...].firstIndex(where: { $0.isWhitespace })
                        ?? sanitizedText.endIndex
            }
            speakingText = String(sanitizedText[..<endIndex])
        }
    }

    /// Schedules buffered text for speech. Always flushes complete paragraph
    /// blocks (`\n\n`); within the remainder, applies the active engine's
    /// streaming chunking strategy.
    private func tryScheduleBuffered() {
        var remaining = String(contentBuffer.dropFirst(spokenOffset))

        // Paragraph breaks first (highest-priority boundary, every strategy).
        while let range = remaining.range(of: "\n\n") {
            let block = String(remaining[..<range.upperBound])
            let trimmed = block.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                queueUtterance(trimmed)
                spokenOffset += block.count
            }
            remaining = String(remaining[range.upperBound...])
        }

        // Then apply the engine's streaming sentence-chunking policy.
        switch currentChunkingStrategy.streaming {
        case .paragraphsOnly:
            return
        case .eager(let minSize):
            while let splitPoint = remaining.firstSentenceBoundary(after: minSize) {
                let block = String(remaining[..<splitPoint])
                let trimmed = block.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    queueUtterance(trimmed)
                    spokenOffset += block.count
                }
                remaining = String(remaining[splitPoint...])
            }
        case .bufferedBatch(let minBuffer):
            guard remaining.count >= minBuffer else { return }
            if let splitPoint = remaining.rangeOfLastSentenceBoundary() {
                let block = String(remaining[..<splitPoint])
                let trimmed = block.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    queueUtterance(trimmed)
                    spokenOffset += block.count
                }
            }
        }
    }

    private func queueUtterance(_ text: String) {
        let sanitized = Self.sanitizeForSpeech(text)
        guard !sanitized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        // Track original text for progress display (FIFO — append so duplicates
        // resolve in the order they were queued).
        utteranceQueue.append((sanitized: sanitized, original: text))

        // Check if the voice changed mid-turn (e.g. via SetPresentationTool).
        refreshSynthesizerIfNeeded()

        pendingUtterances += 1
        synthesizer.speak(sanitized)
    }

    /// Swaps the synthesizer if the voice or engine has changed since last resolution.
    private func refreshSynthesizerIfNeeded() {
        let language = LanguageManager().currentLanguage
        let bestEngine = resolver.bestReadyProvider(for: language).engineKind
        guard resolvedEngineKind != bestEngine || resolvedVoiceID != voiceIdentifier else { return }

        let voices = resolver.voices(for: language)
        let voice = voices.first { $0.identifier == voiceIdentifier }
        setSynthesizer(resolver.resolve(voice: voice, language: language))
        resolvedEngineKind = bestEngine
        resolvedVoiceID = voiceIdentifier
    }

    private func finishOneShot() {
        currentText = nil
        isSpeaking = false
        speakingText = ""
        spokenPrefix = ""
        pendingUtterances = 0
        isOneShotMode = false
        DispatchQueue.main.async { UIApplication.shared.isIdleTimerDisabled = false }
        // Deactivate audio session off the main thread to avoid blocking the UI.
        DispatchQueue.global(qos: .userInitiated).async {
            try? AVAudioSession.sharedInstance().setActive(
                false, options: .notifyOthersOnDeactivation
            )
        }
        onComplete?()
    }

    private func completeStreaming() {
        isSpeaking = false
        onComplete?()
    }
}

/// Preview stub.
struct PreviewSpeechService: SpeechService {
    var isSpeaking: Bool {
        false
    }

    var isPreparingEngine: Bool {
        false
    }

    var isBuffering: Bool {
        false
    }

    var currentText: String? {
        nil
    }

    var voiceIdentifier: String?
    var speakingText: String {
        ""
    }

    var onComplete: (() -> Void)?
    var onAudioStarted: (() -> Void)?
    func speak(_ text: String) {}
    func stop() {}
    func feedDelta(_ delta: String) {}
    func finish() {}
    func cancel() {}
    func reset() {}
}

// MARK: - String Helpers

private extension String {
    /// Returns the index *after* the first sentence-ending punctuation
    /// (`.`, `!`, `?`) or single newline at character offset ≥ `minOffset`.
    /// Returns `nil` if no qualifying boundary exists.
    func firstSentenceBoundary(after minOffset: Int) -> String.Index? {
        for (i, char) in enumerated() where i >= minOffset && ".!?\n".contains(char) {
            return self.index(self.startIndex, offsetBy: i + 1)
        }
        return nil
    }

    /// Returns the index *after* the **last** sentence-ending punctuation
    /// or single newline. Returns `nil` if no boundary is found.
    func rangeOfLastSentenceBoundary() -> String.Index? {
        var lastBoundary: String.Index?
        for (i, char) in enumerated() where ".!?\n".contains(char) {
            lastBoundary = self.index(self.startIndex, offsetBy: i + 1)
        }
        return lastBoundary
    }

    /// Splits the string into utterance-sized chunks per the given chunking
    /// policy. Used by `DefaultSpeechService.speak()` for one-shot playback;
    /// streaming uses its own incremental scanner.
    func chunked(by strategy: SentenceChunking) -> [String] {
        switch strategy {
        case .paragraphsOnly:
            let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? [] : [trimmed]

        case .eager(let minSize):
            var chunks: [String] = []
            var remaining = self
            while let split = remaining.firstSentenceBoundary(after: minSize) {
                let chunk = String(remaining[..<split])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !chunk.isEmpty { chunks.append(chunk) }
                remaining = String(remaining[split...])
            }
            let tail = remaining.trimmingCharacters(in: .whitespacesAndNewlines)
            if !tail.isEmpty { chunks.append(tail) }
            return chunks

        case .bufferedBatch:
            // One-shot has the entire text up front, so the "wait for buffer"
            // semantics of bufferedBatch don't apply — fall back to keeping
            // the paragraph intact, matching the historical PocketTTS path.
            let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? [] : [trimmed]
        }
    }
}
