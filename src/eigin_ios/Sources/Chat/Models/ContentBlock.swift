import Foundation

struct ContentBlock: Identifiable, Equatable {
    let id: String
    let kind: BlockKind
    var text: String
    var language: String?
}

enum BlockKind: Equatable {
    case paragraph
    case code
    case table
    case math
    case list
    case divider
    case heading(level: Int)

    /// Whether the shared markdown renderer draws this kind. Code, tables, dividers,
    /// headings and math have their own Eigin views.
    var usesMarkdownRenderer: Bool {
        switch self {
        case .paragraph, .list: true
        case .code, .table, .divider, .heading, .math: false
        }
    }
}

extension ContentBlock {
    static func split(_ text: String, messageID: String) -> [ContentBlock] {
        guard !text.isEmpty else { return [] }

        var blocks: [ContentBlock] = []
        var currentText = ""
        var currentKind: BlockKind = .paragraph
        var blockIndex = 0

        var inCodeFence = false
        var codeFenceContent = ""
        var codeFenceLanguage: String? = nil
        // Leading spaces on the opening fence, stripped from each content line so
        // list-nested code isn't indented inside its card.
        var codeFenceIndent = 0
        var inMathBlock = false
        var mathContent = ""
        var inTable = false
        var tableLines: [String] = []
        var inList = false
        var listContent = ""

        func flushParagraph() {
            defer {
                currentText = ""
                currentKind = .paragraph
            }
            // Blank lines leave a lone newline in `currentText`; don't emit that as an
            // empty paragraph.
            guard !currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return
            }
            let id = "\(messageID)-block-\(blockIndex)"
            blocks.append(ContentBlock(id: id, kind: currentKind, text: currentText))
            blockIndex += 1
        }

        func flushCode() {
            guard !codeFenceContent.isEmpty else { return }
            let id = "\(messageID)-block-\(blockIndex)"
            blocks.append(ContentBlock(
                id: id,
                kind: .code,
                text: codeFenceContent,
                language: codeFenceLanguage
            ))
            blockIndex += 1
            codeFenceContent = ""
            codeFenceLanguage = nil
            inCodeFence = false
        }

        func flushMath() {
            guard !mathContent.isEmpty else { return }
            let id = "\(messageID)-block-\(blockIndex)"
            blocks.append(ContentBlock(id: id, kind: .math, text: mathContent))
            blockIndex += 1
            mathContent = ""
            inMathBlock = false
        }

        func flushTable() {
            guard !tableLines.isEmpty else { return }
            let id = "\(messageID)-block-\(blockIndex)"
            blocks.append(ContentBlock(
                id: id,
                kind: .table,
                text: tableLines.joined(separator: "\n")
            ))
            blockIndex += 1
            tableLines = []
            inTable = false
        }

        func flushList() {
            guard !listContent.isEmpty else { return }
            let id = "\(messageID)-block-\(blockIndex)"
            blocks.append(ContentBlock(id: id, kind: .list, text: listContent))
            blockIndex += 1
            listContent = ""
            inList = false
        }

        func appendHeading(level: Int, content: String) {
            let id = "\(messageID)-block-\(blockIndex)"
            blocks.append(ContentBlock(id: id, kind: .heading(level: level), text: content))
            blockIndex += 1
        }

        /// Parses an ATX heading into its level and text, or nil if the line isn't one.
        /// 1-6 `#` then a space; any closing run of `#` is dropped.
        func atxHeading(_ trimmed: String) -> (level: Int, content: String)? {
            var level = 0
            for character in trimmed {
                if character == "#" { level += 1 } else { break }
            }
            guard (1 ... 6).contains(level), trimmed.dropFirst(level).first == " " else {
                return nil
            }
            var content = trimmed.dropFirst(level).trimmingCharacters(in: .whitespaces)
            if let closing = content.range(of: #"\s#+$"#, options: .regularExpression) {
                content = String(content[..<closing.lowerBound])
                    .trimmingCharacters(in: .whitespaces)
            }
            return (level, content)
        }

        func flushDivider() {
            // Collapse a run of rules into one; models stack two or three and drawing
            // each is just noise.
            guard blocks.last?.kind != .divider else { return }
            let id = "\(messageID)-block-\(blockIndex)"
            blocks.append(ContentBlock(id: id, kind: .divider, text: ""))
            blockIndex += 1
        }

        /// Opens a fenced code block from its opening line, recording its indentation
        /// and language. The caller flushes whatever block preceded it first.
        func openCodeFence(_ line: String, _ trimmed: String) {
            inCodeFence = true
            codeFenceContent = ""
            codeFenceIndent = line.prefix(while: { $0 == " " }).count
            let lang = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
            codeFenceLanguage = lang.isEmpty ? nil : lang
        }

        /// Drops up to `count` leading spaces so list-nested code isn't indented in its card.
        func stripIndent(_ line: String, by count: Int) -> String {
            guard count > 0 else { return line }
            var body = Substring(line)
            var removed = 0
            while removed < count, body.first == " " {
                body = body.dropFirst()
                removed += 1
            }
            return String(body)
        }

        func isHorizontalRule(_ line: String) -> Bool {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.count >= 3 else { return false }
            let firstChar = trimmed.first!
            return trimmed.allSatisfy { $0 == firstChar && ($0 == "-" || $0 == "*" || $0 == "_") }
        }

        let lines = text.components(separatedBy: "\n")
        var i = 0

        while i < lines.count {
            let line = lines[i]

            if inCodeFence {
                let fence = line.trimmingCharacters(in: .whitespaces)
                if fence.hasPrefix("```"),
                   fence.dropFirst(3).trimmingCharacters(in: .whitespaces).isEmpty
                {
                    flushCode()
                } else {
                    codeFenceContent += (codeFenceContent.isEmpty ? "" : "\n")
                        + stripIndent(line, by: codeFenceIndent)
                }
                i += 1
                continue
            }

            if inMathBlock {
                if line.contains("$$"), line.replacingOccurrences(of: "$$", with: "")
                    .trimmingCharacters(in: .whitespaces).isEmpty
                {
                    flushMath()
                } else {
                    mathContent += (mathContent.isEmpty ? "" : "\n") + line
                }
                i += 1
                continue
            }

            if inTable {
                if line.trimmingCharacters(in: .whitespaces).isEmpty {
                    flushTable()
                    continue
                }
                if !line.hasPrefix("|") {
                    flushTable()
                    continue
                }
                tableLines.append(line)
                i += 1
                continue
            }

            if inList {
                let trimmed = line.trimmingCharacters(in: .whitespaces)

                // Code fenced in a list item gets its own card, so end the list and
                // open the fence.
                if trimmed.hasPrefix("```") {
                    flushList()
                    openCodeFence(line, trimmed)
                    i += 1
                    continue
                }

                // A rule right after a list ends it. Caught here so it renders as our
                // divider.
                if isHorizontalRule(trimmed) {
                    flushList()
                    flushDivider()
                    i += 1
                    continue
                }

                // A heading right after a list ends it and gets its own block.
                if let heading = atxHeading(trimmed) {
                    flushList()
                    appendHeading(level: heading.level, content: heading.content)
                    i += 1
                    continue
                }

                let isListLine = trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") ||
                    trimmed.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil

                if trimmed.isEmpty {
                    // A blank line ends the list block cleanly
                    flushList()
                    // Don't add the blank line to currentText — the next non-empty
                    // line will start a fresh paragraph naturally
                } else if isListLine {
                    listContent += (listContent.isEmpty ? "" : "\n") + line
                } else if line.first?.isWhitespace == true {
                    // Indented content (a nested block quote, a wrapped line, ...) still
                    // belongs to the open list item, so it stays in the list's text.
                    listContent += (listContent.isEmpty ? "" : "\n") + line
                } else {
                    // Unindented, non-list content ends the list and begins a paragraph.
                    flushList()
                    currentText += line
                }
                i += 1
                continue
            }

            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                flushParagraph()
                openCodeFence(line, trimmed)
            } else if trimmed == "$$" {
                flushParagraph()
                inMathBlock = true
                mathContent = ""
            } else if let heading = atxHeading(trimmed) {
                // Headings are Eigin's own block, so they can be styled and uppercased.
                flushParagraph()
                appendHeading(level: heading.level, content: heading.content)
            } else if trimmed.hasPrefix("|") && i + 1 < lines.count {
                let nextLine = lines[i + 1].trimmingCharacters(in: .whitespaces)
                let cleaned = nextLine.replacingOccurrences(of: "|", with: "")
                let isTableSeparator = cleaned.contains("-")
                    && cleaned.allSatisfy { $0 == "-" || $0 == ":" || $0.isWhitespace }
                // Models often omit the header or separator. Two pipe rows in a row is
                // enough: prose doesn't start two lines running with a pipe.
                if isTableSeparator || nextLine.hasPrefix("|") {
                    flushParagraph()
                    inTable = true
                    tableLines = [line]
                } else {
                    currentText += (currentText.isEmpty ? "" : "\n") + line
                }
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") ||
                trimmed.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil
            {
                flushParagraph()
                inList = true
                listContent = line
            } else if isHorizontalRule(trimmed) {
                // Headings are ATX-only (`#`), so a rule-shaped line is always a divider.
                flushParagraph()
                flushDivider()
            } else if trimmed.isEmpty {
                let prevTrimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !prevTrimmed.isEmpty, !currentText.hasSuffix("\n\n") {
                    let twoNewlinesCount = currentText.count(where: { $0 == "\n" })
                    if twoNewlinesCount >= 1 {
                        flushParagraph()
                    } else {
                        currentText += "\n"
                    }
                } else if currentText.hasSuffix("\n\n") {
                    flushParagraph()
                } else {
                    currentText += "\n"
                }
            } else {
                currentText += (currentText.isEmpty ? "" : "\n") + line
            }

            i += 1
        }

        if inCodeFence {
            flushCode()
        } else if inMathBlock {
            flushMath()
        } else if inTable {
            flushTable()
        } else if inList {
            flushList()
        } else if !currentText.isEmpty {
            flushParagraph()
        }

        return blocks
    }
}
