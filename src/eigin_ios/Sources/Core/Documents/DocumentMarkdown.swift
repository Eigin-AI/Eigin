import Foundation

/// Renders recognized table spans as Markdown while preserving surrounding text.
enum DocumentMarkdown {
    static func render(transcript: String, tables: [[[String]]]) -> String {
        var text = transcript
        for rows in tables {
            guard let first = rows.first, !first.isEmpty else { continue }
            let tableText = rows.flatMap { $0 }.joined(separator: "\n")
            // Replace only an exact table span to avoid duplicating or dropping source text.
            guard !tableText.isEmpty, let range = text.range(of: tableText) else { continue }
            text.replaceSubrange(range, with: table(rows))
        }
        return text
    }

    private static func table(_ rows: [[String]]) -> String {
        rows.enumerated().flatMap { index, cells -> [String] in
            let row = "| " + cells.map(escape).joined(separator: " | ") + " |"
            guard index == 0 else { return [row] }
            let separator = "| " + Array(repeating: "---", count: cells.count)
                .joined(separator: " | ") + " |"
            return [row, separator]
        }.joined(separator: "\n")
    }

    private static func escape(_ cell: String) -> String {
        cell.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\n", with: "<br>")
    }
}
