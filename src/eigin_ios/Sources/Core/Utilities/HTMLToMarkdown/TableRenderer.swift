import Foundation
import SwiftSoup

/// Renders `<table>` as a GFM pipe table.
struct TableRenderer {
    let baseURL: URL?

    func render(_ table: Element) -> String? {
        let rows = orderedRows(table)
        guard !rows.isEmpty else { return nil }

        let grid = rows.map { row in
            cells(of: row).map { cell(of: $0) }
        }

        // Column count = widest row (ragged tables keep all content).
        guard let columnCount = grid.map(\.count).max(), columnCount > 0 else { return nil }

        var lines: [String] = []
        let headerRow = grid.first!

        lines.append(pipeRow(headerRow, columnCount: columnCount))
        lines
            .append("|" + Array(repeating: " --- ", count: columnCount)
                .joined(separator: "|") + "|")
        for row in grid.dropFirst() {
            lines.append(pipeRow(row, columnCount: columnCount))
        }
        return lines.joined(separator: "\n")
    }

    /// All `tr` rows in document order; the first row becomes the header.
    private func orderedRows(_ table: Element) -> [Element] {
        let rows = (try? table.getElementsByTag("tr"))?.array() ?? []
        // Drop rows nested inside inner tables — they belong to the inner table.
        return rows.filter { row in
            row.parents().array().first { $0.tagName() == "table" }.map { $0 == table } ?? true
        }
    }

    private func cells(of row: Element) -> [Element] {
        ((try? row.select("th, td"))?.array() ?? [])
            .filter { $0.parents().array().first { $0.tagName() == "tr" }.map { $0 == row } ?? true
            }
    }

    private func cell(of element: Element) -> String {
        // Escape pipes so cell content (incl. code spans) can't break the row.
        Renderer(baseURL: baseURL).renderInlineParagraph(element)
            .replacingOccurrences(of: "|", with: "\\|")
    }

    private func pipeRow(_ cells: [String], columnCount: Int) -> String {
        var padded = cells
        while padded.count < columnCount {
            padded.append("")
        }
        return "|" + padded.map { " \($0) " }.joined(separator: "|") + "|"
    }
}
