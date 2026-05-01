import Foundation

struct ContentBlock: Identifiable, Equatable {
    let id: String
    let kind: BlockKind
    var text: String
}

enum BlockKind: Equatable {
    case paragraph
    case code
    case table
    case math
    case list
    case divider
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
        var inMathBlock = false
        var mathContent = ""
        var inTable = false
        var tableLines: [String] = []
        var inList = false
        var listContent = ""

        func flushParagraph() {
            guard !currentText.isEmpty else { return }
            let id = "\(messageID)-block-\(blockIndex)"
            blocks.append(ContentBlock(id: id, kind: currentKind, text: currentText))
            blockIndex += 1
            currentText = ""
            currentKind = .paragraph
        }

        func flushCode() {
            guard !codeFenceContent.isEmpty else { return }
            let id = "\(messageID)-block-\(blockIndex)"
            blocks.append(ContentBlock(id: id, kind: .code, text: codeFenceContent))
            blockIndex += 1
            codeFenceContent = ""
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

        func flushDivider() {
            let id = "\(messageID)-block-\(blockIndex)"
            blocks.append(ContentBlock(id: id, kind: .divider, text: ""))
            blockIndex += 1
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
                if line.hasPrefix("```"),
                   line.dropFirst(3).trimmingCharacters(in: .whitespaces).isEmpty
                {
                    flushCode()
                } else {
                    codeFenceContent += (codeFenceContent.isEmpty ? "" : "\n") + line
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
                let isListLine = trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") ||
                    trimmed.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil

                if trimmed.isEmpty {
                    // A blank line ends the list block cleanly
                    flushList()
                    // Don't add the blank line to currentText — the next non-empty
                    // line will start a fresh paragraph naturally
                } else if isListLine {
                    listContent += (listContent.isEmpty ? "" : "\n") + line
                } else {
                    // Non-list content after a list ends the list and begins a paragraph
                    flushList()
                    currentText += line
                }
                i += 1
                continue
            }

            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                flushParagraph()
                inCodeFence = true
                codeFenceContent = ""
            } else if trimmed == "$$" {
                flushParagraph()
                inMathBlock = true
                mathContent = ""
            } else if trimmed.hasPrefix("|") && i + 1 < lines.count {
                let nextLine = lines[i + 1].trimmingCharacters(in: .whitespaces)
                let cleaned = nextLine.replacingOccurrences(of: "|", with: "")
                let isTableSeparator = cleaned.contains("-")
                    && cleaned.allSatisfy { $0 == "-" || $0 == ":" || $0.isWhitespace }
                if isTableSeparator {
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
