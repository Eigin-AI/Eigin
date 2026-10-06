@testable import Eigin
import Foundation

/// Scriptable DictationService double for tests.
final class FakeDictationService: DictationService, @unchecked Sendable {
    var state: AppDictationState = .idle
    var transcription = ""
    var error: String?
    /// Text returned by `finish()`.
    var finishResult = ""
    /// How long `finish()` takes before returning.
    var finishDelay: Duration = .zero
    private(set) var finishCallCount = 0

    func start() {
        state = .listening
    }

    func stop() {
        state = .idle
    }

    func finish() async -> String {
        finishCallCount += 1
        if finishDelay > .zero {
            try? await Task.sleep(for: finishDelay)
        }
        transcription = finishResult
        state = .idle
        return finishResult
    }

    func setLocale(_ locale: Locale) {}
    func setContextualStrings(_ strings: [String]) {}
}
