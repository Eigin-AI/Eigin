import Foundation

// MARK: - Tables

struct TableState {
    var inTable = false
    var lines: [String] = []

    /// A line can open a table when it starts a pipe row and the next line is
    /// a separator or another pipe row. Models often omit the header or the
    /// separator: two pipe rows in a row is enough — prose doesn't start two
    /// lines running with a pipe.
    func canOpen(_ line: String, becauseNextLineIs nextLine: String?) -> Bool {
        guard line.trimmingCharacters(in: .whitespaces).hasPrefix("|"),
              let nextLine
        else { return false }
        let next = nextLine.trimmingCharacters(in: .whitespaces)
        let cleaned = next.replacingOccurrences(of: "|", with: "")
        let isSeparator = cleaned.contains("-")
            && cleaned.allSatisfy { $0 == "-" || $0 == ":" || $0.isWhitespace }
        return isSeparator || next.hasPrefix("|")
    }

    mutating func open(claiming line: String) {
        inTable = true
        lines = [line]
    }

    /// A table continues while rows stay pipe-prefixed and non-blank.
    func continues(with line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && trimmed.hasPrefix("|")
    }

    mutating func claim(_ line: String) {
        lines.append(line)
    }

    /// Resolves the claimed rows into one block: the rows joined by newlines,
    /// so each row stays on its own line.
    func resolve() -> ContentBlock? {
        guard !lines.isEmpty else { return nil }
        return ContentBlock(id: "", kind: .table, text: lines.joined(separator: "\n"))
    }
}

extension BlockSplitter {
    mutating func flushTable() {
        guard let block = table.resolve() else {
            table = TableState()
            return
        }
        append(block)
        table = TableState()
    }
}
