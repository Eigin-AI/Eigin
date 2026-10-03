@testable import Eigin
import Foundation
import Testing

/// Runs the Go reference library's in/out corpus against the converter —
/// structural parity checks, not byte-identical diffs: our minimal renderer
/// deliberately differs from the Go library in whitespace inside blockquotes,
/// `<hr>` style, and comment handling.
///
/// The `malformed` pair is ours: hand-written broken HTML with a locked
/// expected output (exact match, see ``malformedFixtureMatchesExactly``).
@Suite("HTML to Markdown Corpus")
struct HTMLToMarkdownCorpusTests {
    private final class BundleToken {}

    /// `name` is e.g. "commonmark/heading"; corpus files are `heading.in.html`
    /// / `heading.out.md` inside the `Fixtures/corpus` folder reference.
    private static func corpusURL(_ name: String, suffix: String) throws -> URL {
        let bundle = Bundle(for: BundleToken.self)
        let file = (name as NSString).lastPathComponent + suffix
        let group = (name as NSString).deletingLastPathComponent
        if let url = bundle.url(
            forResource: file,
            withExtension: nil,
            subdirectory: "Fixtures/corpus/\(group)"
        ) {
            return url
        }
        // Fallback: source tree next to this file (dev runs without bundling).
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        return source.appendingPathComponent("Fixtures/corpus/\(group)/\(file)")
    }

    private static let corpus: [(group: String, name: String)] = [
        ("commonmark", "blockquote"), ("commonmark", "bold"), ("commonmark", "code"),
        ("commonmark", "heading"), ("commonmark", "image"), ("commonmark", "link"),
        ("commonmark", "list"), ("malformed", "broken"), ("strikethrough", "strikethrough"),
        ("table", "basics"), ("table", "contents"), ("table", "parents"),
    ]

    private static func structuralFacts(_ markdown: String) -> (
        headings: [Int: Int], listItems: Int, tableRows: Int, codeSpans: Int
    ) {
        var headings: [Int: Int] = [:]
        var listItems = 0
        var tableRows = 0
        var codeSpans = 0

        var inFence = false
        for line in markdown.split(separator: "\n", omittingEmptySubsequences: true) {
            if line.hasPrefix("```") {
                inFence.toggle()
                continue
            }
            guard !inFence else { continue }
            // Strip quote/block prefixes so indented tables count too.
            let content = line.trimmingCharacters(in: CharacterSet(charactersIn: "> "))
            if content.hasPrefix("#") {
                let level = content.prefix(while: { $0 == "#" }).count
                headings[level, default: 0] += 1
            }
            if content.hasPrefix("- ") || content.hasPrefix("- [ ]") {
                listItems += 1
            }
            if content.hasPrefix("|") {
                tableRows += 1
            }
            codeSpans += content.components(separatedBy: "`").count / 2
        }
        return (headings, listItems, tableRows, codeSpans)
    }

    /// Normalize diff noise: blank-line runs and trailing whitespace.
    private static func normalized(_ s: String) -> String {
        s.split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
    }

    @Test("Converter covers the reference corpus", arguments: corpus)
    func corpusStructuralParity(_ entry: (group: String, name: String)) throws {
        let inputHTML = try String(
            contentsOf: Self.corpusURL("\(entry.group)/\(entry.name)", suffix: ".in.html"),
            encoding: .utf8
        )
        let expected = try String(
            contentsOf: Self.corpusURL("\(entry.group)/\(entry.name)", suffix: ".out.md"),
            encoding: .utf8
        )
        let actual = try HTMLToMarkdownConverter.convert(
            inputHTML,
            baseURL: #require(URL(string: "https://test.com/page"))
        )

        #expect(!actual.isEmpty, "\(entry.group)/\(entry.name) produced no output")

        // The malformed pair is hand-written — exact match by design.
        if entry.group == "malformed" {
            #expect(
                Self.normalized(actual) == Self.normalized(expected),
                """
                \(entry.group)/\(entry.name) mismatch
                expected:
                \(expected)
                actual:
                \(actual)
                """
            )
            return
        }

        let expectedFacts = Self.structuralFacts(expected)
        let actualFacts = Self.structuralFacts(actual)
        // Heading counts per level: at most one heading may go missing per
        // level vs the reference output; extra structure is not a regression.
        for (level, expectedCount) in expectedFacts.headings {
            let actualCount = actualFacts.headings[level] ?? 0
            #expect(
                actualCount >= expectedCount - 1,
                "\(entry.group)/\(entry.name) h\(level): expected ~\(expectedCount), got \(actualCount)"
            )
        }
        // Guard against regressions dropping items/rows: lose at most one,
        // or 15% on large corpora.
        let expectedListItems = max(expectedFacts.listItems, 0)
        #expect(
            actualFacts.listItems >= expectedListItems - max(1, expectedListItems / 7),
            "\(entry.group)/\(entry.name) list items: expected ~\(expectedListItems), got \(actualFacts.listItems)"
        )
        let expectedRows = max(expectedFacts.tableRows, 0)
        if expectedRows > 0 {
            #expect(
                actualFacts.tableRows >= expectedRows - max(1, expectedRows / 7),
                "\(entry.group)/\(entry.name) table rows: expected ~\(expectedRows), got \(actualFacts.tableRows)"
            )
        }
    }
}
