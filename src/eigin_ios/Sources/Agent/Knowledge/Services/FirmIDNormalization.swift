import Foundation

/// Entity-ID normalization matching Firm's ID convention.
///
/// Firm snake_cases every ID at graph-build time (`firm_core/src/id.rs` runs
/// each ID through `convert_case(Case::Snake)`), so `draft_v1` and `draft_v_1`
/// are the *same* entity in the graph. The Swift store keys entity sources by
/// path, so it must normalize IDs with the same rules — otherwise an update
/// addressed by the normalized ID (`…_v_1`, as returned by Firm) doesn't match
/// the row stored under the raw ID (`…_v1`), and the trial build reports a
/// misleading `EntityAlreadyExists` (issue #285).
///
/// Rules mirror convert_case 0.6's default snake-case split:
/// - delimiters (space, `_`, `-`) are dropped
/// - a new word starts at lowercase→uppercase (`fooBar`), letter↔digit
///   (`v1`, `3D`), and acronym (`HTTPRequest`) boundaries
/// - words join with `_`, lowercased; other characters (like `.`) are kept
///
/// TODO: drop this Swift port when the app links the firm SDK directly and
/// normalization can go through the library itself instead of a mirror of it.
enum FirmIDNormalization {
    /// Returns the Firm-normalized (snake_case) form of `id`.
    static func normalize(_ id: String) -> String {
        words(in: id).map { $0.lowercased() }.joined(separator: "_")
    }

    /// Splits into words using convert_case's default boundaries.
    private static func words(in string: String) -> [String] {
        let chars = Array(string)
        var words: [String] = []
        var word = ""

        for (index, char) in chars.enumerated() {
            if isDelimiter(char) {
                if !word.isEmpty {
                    words.append(word)
                    word = ""
                }
                continue
            }
            // A new word starts before this char at a two-char boundary
            // (`aA`, `a1`, `A1`, `1a`, `1A`) or an acronym boundary (the
            // second of two uppercase letters followed by a lowercase).
            let twoBoundary = index > 0 && isBoundary(chars[index - 1], char)
            let acronymBoundary =
                index > 0 && index + 1 < chars.count
                    && isAcronym(chars[index - 1], char, chars[index + 1])
            if twoBoundary || acronymBoundary {
                if !word.isEmpty {
                    words.append(word)
                }
                word = String(char)
                continue
            }
            word.append(char)
        }
        if !word.isEmpty {
            words.append(word)
        }
        return words
    }

    private static func isDelimiter(_ char: Character) -> Bool {
        char == " " || char == "_" || char == "-"
    }

    private static func isBoundary(_ left: Character, _ right: Character) -> Bool {
        // convert_case only splits digits against letters — punctuation (like
        // the preserved `.`) never forms a boundary (`v1.2` → `v_1.2`).
        switch (isDigit(left), isDigit(right)) {
        case (true, true): false
        case (true, false): isUppercase(right) || isLowercase(right)
        case (false, true): isUppercase(left) || isLowercase(left)
        case (false, false): isLowercase(left) && isUppercase(right)
        }
    }

    /// `AAa`: two uppercase letters followed by a lowercase one. The boundary
    /// sits between the two uppercase letters (`HTTPRequest` → HTTP, Request).
    private static func isAcronym(_ first: Character, _ second: Character, _ third: Character)
        -> Bool
    {
        isUppercase(first) && isUppercase(second) && isLowercase(third)
    }

    /// convert_case treats only ASCII digits as digits, and graphemes with no
    /// distinct upper/lower form (emoji, CJK) as neither.
    private static func isDigit(_ char: Character) -> Bool {
        char.isASCII && char.isNumber
    }

    private static func isUppercase(_ char: Character) -> Bool {
        let scalar = String(char)
        let upper = scalar.uppercased(), lower = scalar.lowercased()
        return upper != lower && scalar == upper
    }

    private static func isLowercase(_ char: Character) -> Bool {
        let scalar = String(char)
        let upper = scalar.uppercased(), lower = scalar.lowercased()
        return upper != lower && scalar == lower
    }
}
