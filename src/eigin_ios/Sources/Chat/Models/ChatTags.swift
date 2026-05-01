import Foundation

/// Centralised registry of injectable XML tag element names used in user messages.
/// Provides a single `stripAll(from:)` method so all display paths stay in sync.
enum ChatTags {
    /// Element names that may appear in outgoing API messages but should be
    /// stripped before displaying content to the user.
    ///
    /// Today this contains only the ephemeral `system_hint` block appended by
    /// the ``Gatekeeper`` — persisted message content itself is never mutated
    /// any more, so there are no tags to strip in stored history. Kept as a
    /// single entry point so any future ephemeral injections can be added here.
    static let allElementNames = ["system_hint"]

    /// Removes all known injectable tags (and surrounding whitespace) for display.
    static func stripAll(from content: String) -> String {
        var result = content
        for name in allElementNames {
            result = stripTag(named: name, from: result)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Finds and removes all occurrences of a given XML element (open+close or self-closing).
    private static func stripTag(named elementName: String, from content: String) -> String {
        var result = content
        while let range = tagRange(in: result, elementName: elementName) {
            result.removeSubrange(range)
        }
        return result
    }

    /// Finds the range of `<elementName ...>...</elementName>` or `<elementName ... />`
    /// in the given content, if present.
    static func tagRange(in content: String, elementName: String) -> Range<String.Index>? {
        let open = "<\(elementName)"
        guard let start = content.range(of: open)?.lowerBound else { return nil }
        let after = content[start...]

        // Self-closing tag
        if let selfClose = after.range(of: "/>") {
            let between = after[start ..< selfClose.lowerBound]
            if !between.contains(">") || between.hasSuffix("/") {
                return start ..< selfClose.upperBound
            }
        }

        // Full tag: find </elementName>
        let closeTag = "</\(elementName)>"
        if let close = after.range(of: closeTag) {
            return start ..< close.upperBound
        }

        return nil
    }
}
