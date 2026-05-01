#!/usr/bin/env swift

import Foundation

let catalogPath = URL(fileURLWithPath: CommandLine.arguments[1])
let outputPath = URL(fileURLWithPath: CommandLine.arguments[2])

struct CatalogEntry {
    let key: String
    let comment: String?
    let paramCount: Int
    let enValue: String?
}

func warn(_ msg: String) {
    FileHandle.standardError.write(("WARNING: " + msg + "\n").data(using: .utf8)!)
}

do {
    let data = try Data(contentsOf: catalogPath)
    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let strings = json["strings"] as? [String: Any]
    else {
        throw NSError(
            domain: "generate-localized",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Invalid catalog format"]
        )
    }

    var entries: [CatalogEntry] = []

    for (key, value) in strings {
        guard let dict = value as? [String: Any] else { continue }
        let segments = key.split(separator: ".", omittingEmptySubsequences: false)
            .map { String($0) }

        guard segments.count >= 2 else {
            warn("Skipping key '\(key)' — must have at least domain.element")
            continue
        }
        guard segments.allSatisfy({ !$0.isEmpty }) else {
            warn("Skipping key '\(key)' — empty segment detected")
            continue
        }
        let domain = segments[0]
        guard isValidSwiftIdentifier(domain) else {
            warn("Skipping key '\(key)' — domain '\(domain)' is not a valid Swift identifier")
            continue
        }

        let comment = dict["comment"] as? String
        let enValue: String? = {
            guard let localizations = dict["localizations"] as? [String: Any],
                  let en = localizations["en"] as? [String: Any],
                  let su = en["stringUnit"] as? [String: Any] else { return nil }
            return su["value"] as? String
        }()
        let paramCount = enValue.map { countFormatParameters(in: $0) } ?? 0
        entries.append(CatalogEntry(
            key: key,
            comment: comment,
            paramCount: paramCount,
            enValue: enValue
        ))
    }

    entries.sort { $0.key < $1.key }

    // Build output using a scope stack to properly open/close nested enums.
    // scopeStack tracks the currently open container path: ["domain", "sub", ...]
    // Depth 0 = inside Localized {}; depth 1 = inside domain enum; etc.
    var output = """
    import Foundation

    /// Auto-generated from Localizable.xcstrings. Do not edit manually.
    enum Localized {
        /// Always returns the bundle for the currently selected language.
        /// Computed each time so language changes are reflected immediately.
        static var bundle: Bundle { .appLanguage }

        private static func get(_ key: String) -> String {
            bundle.localizedString(forKey: key, value: nil, table: nil)
        }

    """

    var scopeStack: [String] = [] // currently open enum path segments

    func indent(depth: Int) -> String {
        String(repeating: "    ", count: depth + 1)
    }

    func closeScopesDownTo(commonLen: Int) {
        while scopeStack.count > commonLen {
            let depth = scopeStack.count - 1 // depth inside Localized
            output += "\(indent(depth: depth))}\n"
            scopeStack.removeLast()
        }
    }

    for entry in entries {
        let segments = entry.key.split(separator: ".", omittingEmptySubsequences: false)
            .map { String($0) }

        // containerPath = all segments except the leaf
        let containerPath = Array(segments.dropLast())
        let leafSegment = segments.last!

        // Find how many leading segments match the current scope
        let commonLen = zip(scopeStack, containerPath).prefix(while: { $0 == $1 }).count

        // Close scopes that no longer match
        closeScopesDownTo(commonLen: commonLen)

        // Open new scopes for diverging segments
        for i in commonLen ..< containerPath.count {
            let seg = containerPath[i]
            let depth = i // scopeStack.count after pushing this one = i + 1; enum is at depth i
            let pascalSeg = safeEnumName(seg.pascalCased)
            output += "\(indent(depth: depth))enum \(pascalSeg) {\n"
            scopeStack.append(seg)
        }

        // Write the leaf member
        let leafDepth = containerPath.count
        let leafIndent = indent(depth: leafDepth)
        let swiftName = escapeIfNeeded(leafSegment.camelCased.sanitizedIdentifier)

        if let comment = entry.comment {
            output += "\(leafIndent)/// \(comment)\n"
        }

        if entry.paramCount > 0 {
            let params = (1 ... entry.paramCount).map { "_ p\($0): String" }.joined(separator: ", ")
            let paramNames = (1 ... entry.paramCount).map { "p\($0)" }.joined(separator: ", ")
            output += "\(leafIndent)static func \(swiftName)(\(params)) -> String {\n"
            output += "\(leafIndent)    String(format: Localized.get(\"\(entry.key)\"), \(paramNames))\n"
            output += "\(leafIndent)}\n"
        } else {
            output += "\(leafIndent)static var \(swiftName): String { Localized.get(\"\(entry.key)\") }\n"
        }
    }

    // Close all remaining open scopes
    closeScopesDownTo(commonLen: 0)

    output += "}\n"

    try output.write(to: outputPath, atomically: true, encoding: .utf8)
    print("Generated \(outputPath.path)")

} catch {
    let msg = "Error: \(error)\n"
    FileHandle.standardError.write(msg.data(using: .utf8)!)
    exit(1)
}

// MARK: - Helpers

private func countFormatParameters(in key: String) -> Int {
    // Count %@, %d, %lld etc. but not %%
    var count = 0
    var i = key.startIndex
    while i < key.endIndex {
        if key[i] == "%" {
            let next = key.index(after: i)
            if next < key.endIndex, key[next] != "%" {
                count += 1
            }
            if next < key.endIndex {
                i = key.index(after: next)
                continue
            }
        }
        i = key.index(after: i)
    }
    return count
}

extension String {
    var pascalCased: String {
        // Split on hyphens and camelCase boundaries, capitalize each word
        let hyphenParts = split(separator: "-", omittingEmptySubsequences: true)
        return hyphenParts.map { part -> String in
            let s = String(part)
            guard !s.isEmpty else { return "" }
            return s.prefix(1).uppercased() + s.dropFirst()
        }.joined()
    }

    var camelCased: String {
        let parts = split(separator: "-", omittingEmptySubsequences: true)
        guard !parts.isEmpty else { return self }
        let first = String(parts[0])
        let rest = parts.dropFirst().map { part -> String in
            let s = String(part)
            guard !s.isEmpty else { return "" }
            return s.prefix(1).uppercased() + s.dropFirst()
        }.joined()
        return first + rest
    }

    /// Strips characters that are not valid in a Swift identifier.
    var sanitizedIdentifier: String {
        String(unicodeScalars.filter { c in
            CharacterSet.letters.union(.decimalDigits).union(CharacterSet(charactersIn: "_"))
                .contains(c)
        })
    }
}

/// Renames pascal-cased enum container names that conflict with Swift built-ins.
/// `Type` conflicts with the `foo.Type` metatype expression and cannot be used as a nested type
/// name.
private func safeEnumName(_ name: String) -> String {
    switch name {
    case "Type": "Kind"
    default: name
    }
}

private func escapeIfNeeded(_ identifier: String) -> String {
    // Statement and declaration keywords that cannot be used as member names without backticks
    switch identifier {
    case "break", "case", "catch", "continue", "default", "defer", "do", "else",
         "fallthrough", "for", "guard", "if", "in", "repeat", "return", "throw",
         "try", "where", "while", "class", "deinit", "enum", "extension", "func",
         "import", "init", "inout", "let", "operator", "protocol", "struct",
         "subscript", "typealias", "var", "as", "false", "is", "nil", "self",
         "Self", "super", "true", "type", "Type", "private", "fileprivate",
         "internal", "public", "open", "static", "override", "mutating",
         "nonisolated", "isolated", "lazy", "weak", "unowned", "inherited":
        "`\(identifier)`"
    default:
        identifier
    }
}

private func isValidSwiftIdentifier(_ str: String) -> Bool {
    guard let first = str.first, first.isLetter || first == "_" else { return false }
    for char in str {
        if !char.isLetter, !char.isNumber, char != "_", char != "-" { return false }
    }
    return true
}
