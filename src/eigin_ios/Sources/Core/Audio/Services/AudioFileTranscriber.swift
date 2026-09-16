import AVFoundation
import Factory
import Speech

/// Transcribes an audio file on-device with SpeechAnalyzer.
///
/// The watch records a question and ships the file over; the phone holds the
/// configured language and vocabulary, so transcription runs on its side.
/// Prefers ``SpeechTranscriber`` (Apple Intelligence) when the locale's model
/// is installed, falls back to ``DictationTranscriber`` rather than blocking
/// on a download.
enum AudioFileTranscriber {
    /// Chunk size for reading the file into the analyzer.
    private static let chunkFrames: AVAudioFrameCount = 8192

    /// Reads the file in chunks and returns the joined final transcript.
    /// Empty string when nothing was recognized.
    static func transcribe(url: URL, locale: Locale) async throws -> String {
        let file = try AVAudioFile(forReading: url)

        let modules = try await speechModules(for: locale)
        let newAnalyzer = SpeechAnalyzer(modules: modules)

        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: modules
        ) else {
            throw TranscriptionError.noCompatibleFormat
        }

        // Final results collected as they land; the box bridges the
        // result task back to this caller.
        let finals = TranscriptBox()

        // Result iteration task must be running before start() (Apple's pattern).
        let module = modules[0]
        let resultTask = Task {
            if let speech = module as? SpeechTranscriber {
                await iterate(speech.results, into: finals)
            } else if let dictation = module as? DictationTranscriber {
                await iterate(dictation.results, into: finals)
            }
        }

        let (inputSequence, inputBuilder) = AsyncStream<AnalyzerInput>.makeStream()
        try await newAnalyzer.start(inputSequence: inputSequence)

        // Feed the file through the converter in chunks, then end the stream.
        let converter = BufferConverter()
        let format = file.processingFormat
        let totalFrames = AVAudioFrameCount(file.length)
        var offset: AVAudioFramePosition = 0
        while offset < AVAudioFramePosition(totalFrames) {
            guard !Task.isCancelled else { break }
            let frames = AVAudioFrameCount(
                min(AVAudioFramePosition(chunkFrames), AVAudioFramePosition(totalFrames) - offset)
            )
            guard
                let chunk = AVAudioPCMBuffer(
                    pcmFormat: format, frameCapacity: frames
                )
            else { break }
            chunk.frameLength = frames
            file.framePosition = offset
            try file.read(into: chunk, frameCount: frames)
            offset += AVAudioFramePosition(frames)

            let converted = try converter.convert(chunk, to: analyzerFormat)
            inputBuilder.yield(AnalyzerInput(buffer: converted))
        }
        inputBuilder.finish()

        // Drain everything through the end of input, then collect results.
        try await newAnalyzer.finalizeAndFinishThroughEndOfInput()
        await resultTask.value

        return finals.joined()
    }

    // MARK: - Transcriber selection

    /// SpeechTranscriber when the locale's model is installed, DictationTranscriber
    /// otherwise. Kicks off a background model download when it can, so the next
    /// transcription finds it installed.
    private static func speechModules(for locale: Locale) async throws -> [any SpeechModule] {
        if SpeechTranscriber.isAvailable,
           let canonical = await SpeechTranscriber.supportedLocale(equivalentTo: locale)
        {
            let installed = await SpeechTranscriber.installedLocales
            if installed.contains(where: {
                $0.identifier(.bcp47) == canonical.identifier(.bcp47)
            }) {
                return [
                    SpeechTranscriber(
                        locale: canonical,
                        transcriptionOptions: [],
                        reportingOptions: [],
                        attributeOptions: []
                    ),
                ]
            }
            // Download in the background so a later transcription finds it.
            let transcriber = SpeechTranscriber(
                locale: canonical,
                transcriptionOptions: [],
                reportingOptions: [],
                attributeOptions: []
            )
            Task.detached(priority: .utility) {
                if let request = try? await AssetInventory.assetInstallationRequest(
                    supporting: [transcriber]
                ) {
                    try? await request.downloadAndInstall()
                }
            }
        }

        return [DictationTranscriber(locale: locale, preset: .shortDictation)]
    }

    private static func iterate<S: AsyncSequence>(_ results: S, into box: TranscriptBox) async
        where S.Element: TranscriberResult
    {
        // A failing result stream just ends the iteration — the finals
        // collected so far are still the transcription.
        do {
            for try await result in results {
                let text = String(result.text.characters)
                box.append(text, isFinal: result.isFinal)
            }
        } catch {}
    }

    enum TranscriptionError: LocalizedError {
        case noCompatibleFormat

        var errorDescription: String? {
            switch self {
            case .noCompatibleFormat: "No compatible audio format available."
            }
        }
    }
}

/// Thread-safe collector for final transcription results.
private final class TranscriptBox: @unchecked Sendable {
    private let lock = NSLock()
    private var parts: [String] = []

    func append(_ text: String, isFinal: Bool) {
        guard isFinal, !text.isEmpty else { return }
        lock.lock()
        parts.append(text)
        lock.unlock()
    }

    func joined() -> String {
        lock.lock()
        defer { lock.unlock() }
        return parts.joined(separator: " ")
    }
}
