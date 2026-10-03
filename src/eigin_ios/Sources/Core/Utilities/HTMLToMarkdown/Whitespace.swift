import Foundation

/// Whitespace normalization between and inside blocks.
enum Whitespace {
    /// Collapse all whitespace runs (incl. `<br>`-derived newlines) to single
    /// spaces and trim. Used for inline flow inside one block.
    static func collapse(_ input: String) -> String {
        var result = ""
        result.reserveCapacity(input.count)
        var inWhitespace = false

        for character in input {
            if character.isWhitespace || character == "\n" || character == "\t" {
                inWhitespace = true
                continue
            }
            if inWhitespace, !result.isEmpty {
                result.append(" ")
            }
            inWhitespace = false
            result.append(character)
        }
        return result
    }

    /// Join block strings with blank lines, collapsing excess newlines.
    static func joinBlocks(_ blocks: [String]) -> String {
        let joined = blocks.filter { !$0.isEmpty }.joined(separator: "\n\n")
        var result = ""
        var previousWasBlank = false

        for character in joined {
            if character == "\n" {
                if previousWasBlank { continue }
                if result.hasSuffix("\n") {
                    previousWasBlank = true
                }
                result.append("\n")
            } else {
                previousWasBlank = character == " " ? previousWasBlank : false
                result.append(character)
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
