import HighlightSwift
import SwiftUI

/// Serializes syntax highlighting across the whole app.
///
/// Each highlight builds its result through WebKit's HTML importer
/// (`NSAttributedString` with an HTML document type), which is expensive and contends
/// badly when several blocks run at once. A message full of code seals many blocks in a
/// burst; without serialization those imports pile up and stall the UI. Chaining the work
/// so one highlight finishes before the next begins keeps the main thread clear.
///
/// A plain actor wouldn't serialize this: actor reentrancy lets a second call start while
/// the first is suspended at its `await`. The task chain is what enforces one-at-a-time.
actor HighlightQueue {
    static let shared = HighlightQueue()

    private let highlighter = Highlight()
    private var tail: Task<AttributedString?, Never>?

    func attributedText(
        _ code: String,
        language: String,
        css: String
    ) async -> AttributedString? {
        let previous = tail
        let task = Task { [highlighter] in
            // Wait for the prior highlight to finish before starting this one.
            _ = await previous?.value
            return try? await highlighter.attributedText(
                code,
                language: language,
                colors: .custom(css: css)
            )
        }
        tail = task
        return await task.value
    }
}
