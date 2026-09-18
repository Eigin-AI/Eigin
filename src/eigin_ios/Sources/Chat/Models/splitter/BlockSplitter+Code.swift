import Foundation

// MARK: - Code fences

/// A fence's streaming state: open, what it has claimed, and the leading
/// indent stripped from each content line so list-nested code isn't indented
/// inside its card.
struct CodeFenceState {
    var inFence = false
    var content = ""
    var language: String?
    var indent = 0

    mutating func open(_ line: String, trimmed: String) {
        inFence = true
        content = ""
        indent = line.prefix(while: { $0 == " " }).count
        let lang = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
        language = lang.isEmpty ? nil : lang
    }

    /// True when the line is the closing fence.
    func closes(with line: String) -> Bool {
        let fence = line.trimmingCharacters(in: .whitespaces)
        return fence.hasPrefix("```")
            && fence.dropFirst(3).trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Adds a content line, de-indented.
    mutating func claim(_ line: String) {
        content += (content.isEmpty ? "" : "\n") + deindent(line)
    }

    /// Resolves the fence into a code block (`blocks` gains one), open or not:
    /// an unclosed empty fence still closes.
    mutating func flush() -> ContentBlock? {
        defer {
            content = ""
            language = nil
            inFence = false
        }
        guard !content.isEmpty else { return nil }
        return ContentBlock(id: "", kind: .code, text: content, language: language)
    }

    /// Drops up to `indent` leading spaces, so list-nested code isn't indented
    /// in its card.
    private func deindent(_ line: String) -> String {
        guard indent > 0 else { return line }
        var body = Substring(line)
        var removed = 0
        while removed < indent, body.first == " " {
            body = body.dropFirst()
            removed += 1
        }
        return String(body)
    }
}

extension BlockSplitter {
    mutating func openCodeFence(_ line: String, _ trimmed: String) {
        code.open(line, trimmed: trimmed)
    }

    /// Resolves the fence: an ID is minted here, where the block index lives.
    mutating func flushCode() {
        guard let block = code.flush() else { return }
        append(block)
    }

    /// Overload keeping emit-by-fields in one place.
    mutating func append(_ block: ContentBlock) {
        append(block.kind, text: block.text, language: block.language)
    }
}
