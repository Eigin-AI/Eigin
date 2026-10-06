import Factory
import Observation

/// Commits dictation on send or on returning to the keyboard: finalizes the
/// transcription under a bounded wait and combines it with any text typed
/// before the dictation started.
///
/// A commit guards itself against re-entry: while finalization is in flight
/// (up to the finalization timeout), further commits return `nil` instead of
/// racing the pending one — a send tap during the window can't double-send
/// or send with the tail still missing.
@MainActor
@Observable
final class DictationCommit {
    private(set) var isFinishing = false
    private var dictation: (any DictationService)?

    /// Test seam; production resolves the shared service from the container.
    init(dictation: (any DictationService)? = nil) {
        self.dictation = dictation
    }

    private var service: any DictationService {
        if let dictation { return dictation }
        let resolved = Container.shared.dictationService()
        dictation = resolved
        return resolved
    }

    /// Finalizes dictation and returns the full committed text, or `nil`
    /// when another commit is already in flight.
    func commit(before: String) async -> String? {
        guard !isFinishing else { return nil }
        isFinishing = true
        defer { isFinishing = false }
        let dictated = await service.finish()
        return Self.combining(before, dictated)
    }

    /// Combines pre-dictation text with the finalized dictation result.
    static func combining(_ before: String, _ dictated: String) -> String {
        let dictated = dictated.trimmingCharacters(in: .whitespacesAndNewlines)
        return switch (before.isEmpty, dictated.isEmpty) {
        case (true, true): ""
        case (true, false): dictated
        case (false, true): before
        case (false, false): before + " " + dictated
        }
    }
}
