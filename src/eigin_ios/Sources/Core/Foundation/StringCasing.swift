import Foundation

extension String {
    /// Converts a string from any common casing convention to Title Case.
    ///
    /// Handles snake_case, camelCase, PascalCase, kebab-case, dot.case,
    /// and slash/separated strings. Falls back to splitting on whitespace
    /// if no separator or case boundary is detected.
    ///
    /// Examples:
    /// - `"list_tools"` → `"List Tools"`
    /// - `"listTools"` → `"List Tools"`
    /// - `"ListTools"` → `"List Tools"`
    /// - `"list-tools"` → `"List Tools"`
    /// - `"LIST_TOOLS"` → `"List Tools"`
    /// - `"list.tools"` → `"List Tools"`
    /// - `"list tools"` → `"List Tools"`
    /// - `"already Title Case"` → `"Already Title Case"`
    var titleCased: String {
        // Split on common separators first
        let separatorPattern = #/[_\-./\\]+/#
        let hasSeparators = contains(separatorPattern)

        let words: [String] = if hasSeparators {
            split(separator: separatorPattern).map(String.init)
        } else if contains(" ") {
            split(separator: " ").map(String.init)
        } else {
            // Split on camelCase / PascalCase boundaries
            splitCamelCase()
        }

        return words
            .filter { !$0.isEmpty }
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }

    /// Splits a camelCase or PascalCase string into words.
    ///
    /// - `"listTools"` → `["list", "Tools"]`
    /// - `"HTMLParser"` → `["HTML", "Parser"]`
    /// - `"getURLValue"` → `["get", "URL", "Value"]`
    private func splitCamelCase() -> [String] {
        var words: [String] = []
        var current = ""

        let chars = Array(self)
        for i in chars.indices {
            let char = chars[i]
            let isUpper = char.isUppercase
            let prevIsUpper = i > 0 && chars[i - 1].isUppercase
            let nextIsLower = i + 1 < chars.count && chars[i + 1].isLowercase

            if isUpper, !current.isEmpty {
                if !prevIsUpper || nextIsLower {
                    // Boundary: start of new word
                    words.append(current)
                    current = ""
                }
            }
            current.append(char)
        }
        if !current.isEmpty {
            words.append(current)
        }

        return words
    }
}
