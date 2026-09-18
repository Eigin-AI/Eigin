import Foundation

// MARK: - Lists

struct ListState {
    var inList = false
    var content = ""

    mutating func open(claiming line: String) {
        inList = true
        content = line
    }

    /// Whether the line still belongs to the open list: a list item, or
    /// indented content (a nested block quote, a wrapped line, ...).
    func continues(with line: String, trimmed: String) -> Bool {
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
            return true
        }
        if trimmed.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil {
            return true
        }
        return line.first?.isWhitespace == true
    }

    mutating func claim(_ line: String) {
        content += (content.isEmpty ? "" : "\n") + line
    }

    /// Resolves the claimed lines into one block: the lines joined by
    /// newlines, list markdown intact for the renderer.
    func resolve() -> ContentBlock? {
        guard !content.isEmpty else { return nil }
        return ContentBlock(id: "", kind: .list, text: content)
    }
}

extension BlockSplitter {
    mutating func flushList() {
        guard let block = list.resolve() else {
            list = ListState()
            return
        }
        append(block)
        list = ListState()
    }
}
