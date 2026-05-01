#!/usr/bin/env swift

import Foundation

let sourceDir = URL(fileURLWithPath: CommandLine.arguments[1])
let localizedSwiftPath = URL(fileURLWithPath: CommandLine.arguments[2])

do {
    let enumData = try String(contentsOf: localizedSwiftPath, encoding: .utf8)
    let validKeys = extractKeys(from: enumData)

    let swiftFiles = try findSwiftFiles(in: sourceDir)
    var errors: [(path: String, line: Int, key: String)] = []

    let pattern = try NSRegularExpression(pattern: #"String\(localized:\s*"([^"]+)"#)
    let sourcePattern = try NSRegularExpression(pattern: #"Localized\.get\("#)

    for file in swiftFiles {
        let content = try String(contentsOf: file, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)

        for (lineIndex, line) in lines.enumerated() {
            let range = NSRange(line.startIndex..., in: line)

            if sourcePattern.numberOfMatches(in: line, range: range) > 0 {
                continue
            }

            let matches = pattern.matches(in: line, range: range)
            for match in matches {
                guard let keyRange = Range(match.range(at: 1), in: line) else { continue }
                let key = String(line[keyRange])
                if !validKeys.contains(key) {
                    errors.append((path: file.path, line: lineIndex + 1, key: key))
                }
            }
        }
    }

    if !errors.isEmpty {
        let header = "Localization validation failed:\n"
        FileHandle.standardError.write(header.data(using: .utf8)!)
        for error in errors {
            let msg = "\(error.path):\(error.line): unknown localization key '\(error.key)'\n"
            FileHandle.standardError.write(msg.data(using: .utf8)!)
        }
        exit(1)
    }

    print("Validation passed. \(validKeys.count) keys checked.")

} catch {
    let msg = "Error: \(error)\n"
    FileHandle.standardError.write(msg.data(using: .utf8)!)
    exit(1)
}

// MARK: - Helpers

private func extractKeys(from content: String) -> Set<String> {
    var keys: Set<String> = []
    let pattern = try! NSRegularExpression(pattern: #"Localized\.get\("([^"]+)"#)
    let range = NSRange(content.startIndex..., in: content)
    let matches = pattern.matches(in: content, range: range)
    for match in matches {
        if let keyRange = Range(match.range(at: 1), in: content) {
            keys.insert(String(content[keyRange]))
        }
    }
    return keys
}

private func findSwiftFiles(in dir: URL) throws -> [URL] {
    var files: [URL] = []
    let fm = FileManager.default
    guard let enumerator = fm.enumerator(at: dir, includingPropertiesForKeys: [.isDirectoryKey])
    else {
        return files
    }

    while let url = enumerator.nextObject() as? URL {
        let path = url.path
        if path.contains("/.build/") || path.contains("/Pods/") || path
            .contains("/DerivedData/") || path.contains("/Tests/")
        {
            enumerator.skipDescendants()
            continue
        }
        if path.hasSuffix(".swift"), !path.contains("#Preview") {
            files.append(url)
        }
    }
    return files
}
