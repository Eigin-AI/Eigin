import Foundation

/// Result of a tag extraction attempt.
enum ExtractionResult: Equatable {
    /// The tag was found. `reason` is the model's chain-of-thought (nil if not provided).
    case extracted(value: String, reason: String?)
    /// The model produced output but the expected tag was not present.
    case noMatch(rawOutput: String)
    /// The model produced no output.
    case empty
}

/// Parses `<tag reason="...">value</tag>` from model output for structured extraction.
///
/// Not a general XML parser — intentionally limited to the single-tag extraction
/// pattern of `<tag reason="...">value</tag>`.
enum XMLTagParser {
    /// Extracts the value and optional reason from the last occurrence of the given tag.
    ///
    /// Uses the last occurrence to guard against models that echo few-shot examples
    /// before producing their own response.
    static func extract(tag: String, from output: String) -> ExtractionResult {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }

        let open = "<\(tag)"
        let close = "</\(tag)>"

        // Try normal closing tag first
        if let closeRange = trimmed.range(of: close, options: .backwards) {
            // Find the opening tag that precedes this close tag
            let searchRegion = trimmed[trimmed.startIndex ..< closeRange.lowerBound]
            guard let openRange = searchRegion.range(of: open, options: .backwards) else {
                return .noMatch(rawOutput: trimmed)
            }

            // Extract the full opening tag (from "<tag" to the next ">")
            let afterOpen = trimmed[openRange.lowerBound...]
            guard let openCloseAngle = afterOpen.range(of: ">") else {
                return .noMatch(rawOutput: trimmed)
            }
            let openingTag = String(afterOpen[afterOpen.startIndex ..< openCloseAngle.upperBound])

            // Content sits between end of opening tag and start of closing tag
            let contentStart = openCloseAngle.upperBound
            let contentEnd = closeRange.lowerBound
            guard contentStart <= contentEnd else {
                return .noMatch(rawOutput: trimmed)
            }
            let value = trimmed[contentStart ..< contentEnd]
                .trimmingCharacters(in: .whitespacesAndNewlines)

            let reason = parseReason(from: openingTag)
            return .extracted(value: value, reason: reason)
        }

        // Fallback: try self-closing tag <tag ... />
        let selfClose = "/>"
        guard let selfCloseRange = trimmed.range(of: selfClose, options: .backwards) else {
            return .noMatch(rawOutput: trimmed)
        }

        let searchRegion = trimmed[trimmed.startIndex ..< selfCloseRange.lowerBound]
        guard let openRange = searchRegion.range(of: open, options: .backwards) else {
            return .noMatch(rawOutput: trimmed)
        }

        let afterOpen = trimmed[openRange.lowerBound...]
        guard let openCloseAngle = afterOpen.range(of: "/>") else {
            return .noMatch(rawOutput: trimmed)
        }
        let openingTag = String(afterOpen[afterOpen.startIndex ..< openCloseAngle.lowerBound]) + ">"

        let reason = parseReason(from: openingTag)
        return .extracted(value: "", reason: reason)
    }

    // MARK: - Private

    private static func parseReason(from openingTag: String) -> String? {
        // Match reason="..." or reason='...'
        let pattern = #"reason=["']([^"']*)["']"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                  in: openingTag,
                  range: NSRange(openingTag.startIndex..., in: openingTag)
              ),
              let range = Range(match.range(at: 1), in: openingTag)
        else {
            return nil
        }
        let value = String(openingTag[range])
        return value.isEmpty ? nil : value
    }
}
