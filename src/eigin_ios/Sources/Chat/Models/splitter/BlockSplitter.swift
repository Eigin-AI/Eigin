import Foundation

/// Streams raw chat markdown into renderable blocks, in one line-based pass.
///
/// Each construct — code, math, table, list, image — owns its state in a
/// struct of the same shape (whether it's open, what it has claimed) and its
/// own resolution methods, grouped by domain in this type's extensions:
/// `+Code`, `+Math`, `+Table`, `+List`, `+Image`. Between constructs the
/// splitter collects prose in a paragraph buffer.
struct BlockSplitter {
    let messageID: String
    /// Text that may still be arriving: an unclosed construct is held back
    /// whole rather than rendered in a partial state.
    let isStreaming: Bool

    init(messageID: String, isStreaming: Bool) {
        self.messageID = messageID
        self.isStreaming = isStreaming
    }

    private(set) var blocks: [ContentBlock] = []
    /// Prose collected since the last block, possibly mid-paragraph with
    /// soft-break newlines inside.
    private(set) var paragraph = ""
    private var blockIndex = 0

    var code = CodeFenceState()
    var math = MathState()
    var table = TableState()
    var list = ListState()
    var image = ImageState()

    /// Runs the pass over `text` and returns the resolved blocks.
    mutating func scan(_ text: String) -> [ContentBlock] {
        let lines = text.components(separatedBy: "\n")
        /// The line after the current one, for constructs whose opener needs a
        /// look ahead (a table needs its separator row).
        func nextLine() -> String? {
            i + 1 < lines.count ? lines[i + 1] : nil
        }
        var i = 0

        while i < lines.count {
            let line = lines[i]

            if code.inFence {
                if code.closes(with: line) {
                    flushCode()
                } else {
                    code.claim(line)
                }
                i += 1
                continue
            }

            if math.inBlock {
                if math.closes(with: line) {
                    flushMath()
                } else {
                    math.claim(line)
                }
                i += 1
                continue
            }

            if table.inTable {
                if table.continues(with: line) {
                    table.claim(line)
                    i += 1
                } else {
                    flushTable()
                }
                continue
            }

            if list.inList {
                let trimmed = line.trimmingCharacters(in: .whitespaces)

                // Code fenced in a list item gets its own card, so end the list
                // and open the fence.
                if trimmed.hasPrefix("```") {
                    flushList()
                    openCodeFence(line, trimmed)
                    i += 1
                    continue
                }

                // A rule right after a list ends it. Caught here so it renders
                // as our divider.
                if isHorizontalRule(trimmed) {
                    flushList()
                    flushDivider()
                    i += 1
                    continue
                }

                // A heading right after a list ends it and gets its own block.
                if let heading = Self.atxHeading(trimmed) {
                    flushList()
                    append(.heading(level: heading.level), text: heading.content)
                    i += 1
                    continue
                }

                if trimmed.isEmpty {
                    // A blank line ends the list block cleanly; the next
                    // non-empty line starts a fresh paragraph naturally.
                    flushList()
                } else if list.continues(with: line, trimmed: trimmed) {
                    list.claim(line)
                } else {
                    // Unindented, non-list content ends the list and begins a
                    // paragraph.
                    flushList()
                    toParagraph(line)
                }
                i += 1
                continue
            }

            // A held image line is now complete: it either closed into an image
            // card or it wasn't an image. Either way, this line is processed on
            // its own afterwards.
            if image.held != nil {
                flushImage()
            }

            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                flushParagraph()
                openCodeFence(line, trimmed)
            } else if trimmed == "$$" {
                flushParagraph()
                math.open()
            } else if let heading = Self.atxHeading(trimmed) {
                // Headings are Eigin's own block, so they can be styled and
                // uppercased.
                flushParagraph()
                append(.heading(level: heading.level), text: heading.content)
            } else if table.canOpen(line, becauseNextLineIs: nextLine()) {
                flushParagraph()
                table.open(claiming: line)
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") ||
                trimmed.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil
            {
                flushParagraph()
                list.open(claiming: line)
            } else if isHorizontalRule(trimmed) {
                // Headings are ATX-only (`#`), so a rule-shaped line is always
                // a divider.
                flushParagraph()
                flushDivider()
            } else if ImagePatterns.opens(trimmed) {
                flushParagraph()
                if let parsed = ImagePatterns.match(trimmed) {
                    emitImage(parsed)
                } else {
                    // Opens like an image but isn't complete: hold it until the
                    // stream closes the pattern, like a code fence holds until
                    // its closing fence.
                    image.hold(line)
                }
            } else if trimmed.isEmpty {
                collectBlankLine()
            } else {
                toParagraph(line)
            }

            i += 1
        }

        flushAtEnd()
        return blocks
    }

    // MARK: - Paragraph buffer and emitters

    /// Emits the collected prose, then resets the buffer.
    mutating func flushParagraph() {
        defer { paragraph = "" }
        // Blank lines leave a lone newline in the buffer; don't emit that as an
        // empty paragraph.
        guard !paragraph.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        append(.paragraph, text: paragraph)
    }

    /// Adds prose, soft breaks and all, to the paragraph buffer.
    mutating func toParagraph(_ line: String) {
        paragraph += (paragraph.isEmpty ? "" : "\n") + line
    }

    /// Blank lines shape paragraph breaks: a second one (or any after a
    /// double-newline) ends the paragraph; the first joins with a soft break.
    mutating func collectBlankLine() {
        let prevTrimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
        if !prevTrimmed.isEmpty, !paragraph.hasSuffix("\n\n") {
            let twoNewlinesCount = paragraph.count(where: { $0 == "\n" })
            if twoNewlinesCount >= 1 {
                flushParagraph()
            } else {
                paragraph += "\n"
            }
        } else if paragraph.hasSuffix("\n\n") {
            flushParagraph()
        } else {
            paragraph += "\n"
        }
    }

    /// Emits a rule. A run of rules collapses into one: models stack two or
    /// three and drawing each is just noise.
    mutating func flushDivider() {
        guard blocks.last?.kind != .divider else { return }
        append(.divider, text: "")
    }

    mutating func append(_ kind: BlockKind, text: String, language: String? = nil) {
        let id = "\(messageID)-block-\(blockIndex)"
        blocks.append(ContentBlock(id: id, kind: kind, text: text, language: language))
        blockIndex += 1
    }

    /// Parses an ATX heading into its level and text, or nil if the line isn't
    /// one. 1-6 `#` then a space; any closing run of `#` is dropped.
    static func atxHeading(_ trimmed: String) -> (level: Int, content: String)? {
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

    func isHorizontalRule(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3 else { return false }
        let firstChar = trimmed.first!
        return trimmed.allSatisfy { $0 == firstChar && ($0 == "-" || $0 == "*" || $0 == "_") }
    }

    // MARK: - End of pass

    /// Resolves whatever construct is still open. While streaming, an
    /// unclosed image is held for a later chunk; a complete message can only
    /// release it as prose.
    private mutating func flushAtEnd() {
        if code.inFence {
            flushCode()
        } else if math.inBlock {
            flushMath()
        } else if table.inTable {
            flushTable()
        } else if list.inList {
            flushList()
        } else if image.held != nil {
            if isStreaming {
                image.release()
            } else {
                flushImage()
                flushParagraph()
            }
        } else if !paragraph.isEmpty {
            flushParagraph()
        }
    }
}
