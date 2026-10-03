import Foundation

/// Escaping helpers. Only the minimum is escaped to keep output compact, while
/// ensuring text content can't accidentally form Markdown structures or raw HTML.
enum Escaping {
    /// Escape inline text content.
    static func text(_ input: String) -> String {
        var result = ""
        result.reserveCapacity(input.count)

        var atLineStart = true
        var index = 0
        let characters = Array(input)

        while index < characters.count {
            let character = characters[index]

            if character == "\n" {
                result.append("\n")
                atLineStart = true
                index += 1
                continue
            }

            var escaped = false
            if ["\\", "`", "*", "_", "[", "]"].contains(character) {
                result.append("\\")
                result.append(character)
                escaped = true
            } else if character == "<" {
                // "<word" could form raw HTML — escape; lone "<" is harmless.
                let next = index + 1 < characters.count ? characters[index + 1] : nil
                if next.map({ $0.isLetter }) == true {
                    result.append("\\")
                }
                result.append(character)
                escaped = true
            } else if atLineStart, character == "#" {
                result.append("\\#")
                escaped = true
            } else if atLineStart, character == ">" {
                result.append("\\>")
                escaped = true
            } else if atLineStart, ["-", "+"].contains(character) {
                result.append("\\")
                result.append(character)
                escaped = true
            } else if atLineStart, character.isNumber {
                // "1. text" becomes list items — escape the dot if followed by a space.
                if let dotIndex = firstNonDigit(characters, from: index),
                   characters[dotIndex] == ".", dotIndex - index <= 9,
                   dotIndex + 1 < characters.count, characters[dotIndex + 1] == " "
                {
                    result.append(String(characters[index ..< dotIndex]) + "\\.")
                    index = dotIndex + 1
                    atLineStart = false
                    continue
                }
                result.append(character)
            } else {
                result.append(character)
            }

            if !escaped, !character.isWhitespace {
                atLineStart = false
            }
            index += 1
        }

        return result
    }

    private static func firstNonDigit(_ characters: [Character], from index: Int) -> Int? {
        var position = index
        while position < characters.count, characters[position].isNumber {
            position += 1
        }
        return position < characters.count ? position : nil
    }

    /// Wrap text in a code span, sizing the backtick fence around any runs.
    static func codeSpan(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "``" }
        let longest = longestBacktickRun(in: trimmed)
        let ticks = String(repeating: "`", count: longest + 1)
        let pad = trimmed.hasPrefix("`") || trimmed.hasSuffix("`") ? " " : ""
        return ticks + pad + trimmed + pad + ticks
    }

    /// Escape a URL for use inside `(...)` in a link/image.
    static func href(_ url: String) -> String {
        url.replacingOccurrences(of: "(", with: "%28")
            .replacingOccurrences(of: ")", with: "%29")
            .replacingOccurrences(of: " ", with: "%20")
    }

    static func longestBacktickRun(in text: String) -> Int {
        var longest = 0
        var current = 0
        for character in text {
            if character == "`" {
                current += 1
                longest = max(longest, current)
            } else {
                current = 0
            }
        }
        return longest
    }
}
