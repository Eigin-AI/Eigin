import Foundation

/// A GitHub-flavoured markdown table, split into header, column alignments and rows.
///
/// Cells keep their markdown: they hold inline syntax only, which
/// ``MarkdownTableView`` renders with `AttributedString(markdown:)`.
struct MarkdownTable: Equatable {
    enum ColumnAlignment: Equatable {
        case leading
        case center
        case trailing
    }

    /// Empty when the table omits its header row, which models do often enough to matter.
    let headers: [String]
    /// One entry per column, so this is the table's column count.
    let alignments: [ColumnAlignment]
    /// Padded and truncated to the column count, so every row is uniform.
    let rows: [[String]]

    var columnCount: Int {
        alignments.count
    }

    /// Parses a table block. Returns nil when the text isn't a table, which lets the
    /// caller fall back to rendering it as ordinary markdown rather than losing it.
    ///
    /// Handles all three shapes seen in practice: a header with its separator, a
    /// separator alone with the header omitted, and bare rows with neither.
    static func parse(_ markdown: String) -> MarkdownTable? {
        let lines = markdown
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard lines.count >= 2, lines.allSatisfy({ $0.contains("|") }) else { return nil }

        if let alignments = separatorAlignments(lines[1]) {
            let headers = cells(in: lines[0])
            guard headers.count == alignments.count else { return nil }
            return MarkdownTable(
                headers: headers,
                alignments: alignments,
                rows: normalize(lines.dropFirst(2), to: alignments.count)
            )
        }

        if let alignments = separatorAlignments(lines[0]) {
            return MarkdownTable(
                headers: [],
                alignments: alignments,
                rows: normalize(lines.dropFirst(1), to: alignments.count)
            )
        }

        // Bare rows. Every line has to be a pipe row for this not to swallow prose.
        guard lines.allSatisfy({ $0.hasPrefix("|") }) else { return nil }
        let columnCount = cells(in: lines[0]).count
        return MarkdownTable(
            headers: [],
            alignments: Array(repeating: .leading, count: columnCount),
            rows: normalize(lines[...], to: columnCount)
        )
    }

    private static func normalize(
        _ lines: ArraySlice<String>,
        to columnCount: Int
    ) -> [[String]] {
        lines.map { line in
            var row = cells(in: line)
            if row.count < columnCount {
                row += Array(repeating: "", count: columnCount - row.count)
            }
            return Array(row.prefix(columnCount))
        }
    }

    /// Splits a row on unescaped pipes, dropping the optional outer pipes and
    /// unescaping `\|` in the process.
    private static func cells(in line: String) -> [String] {
        var body = Substring(line)
        if body.hasPrefix("|") {
            body = body.dropFirst()
        }
        if body.hasSuffix("|"), !body.hasSuffix("\\|") {
            body = body.dropLast()
        }

        var cells: [String] = []
        var current = ""
        var isEscaped = false
        for character in body {
            if isEscaped {
                if character != "|" {
                    current.append("\\")
                }
                current.append(character)
                isEscaped = false
            } else if character == "\\" {
                isEscaped = true
            } else if character == "|" {
                cells.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(character)
            }
        }
        if isEscaped {
            current.append("\\")
        }
        cells.append(current.trimmingCharacters(in: .whitespaces))
        return cells
    }

    /// Reads a separator row, or nil if the line isn't one. Every cell has to be a valid
    /// spec: a row with one malformed cell is a data row that happens to contain dashes.
    private static func separatorAlignments(_ line: String) -> [ColumnAlignment]? {
        let specs = cells(in: line)
        guard !specs.isEmpty else { return nil }

        var alignments: [ColumnAlignment] = []
        for spec in specs {
            guard spec.contains("-"), spec.allSatisfy({ $0 == "-" || $0 == ":" }) else {
                return nil
            }
            switch (spec.hasPrefix(":"), spec.hasSuffix(":")) {
            case (true, true): alignments.append(.center)
            case (false, true): alignments.append(.trailing)
            default: alignments.append(.leading)
            }
        }
        return alignments
    }
}
