import Foundation

// MARK: - Image cards

/// A standalone image line held while its pattern is incomplete: the way a
/// code fence holds until its closing fence, so a half-streamed `![alt](ur`
/// never shows as markdown text. Given up, it returns to being prose.
struct ImageState {
    /// The held line, when one is held. Nil when nothing is.
    var held: String?

    mutating func hold(_ line: String) {
        held = line
    }

    mutating func release() {
        held = nil
    }
}

/// Image markdown, compiled once rather than per streaming line: `![alt](src)`
/// and `[![alt](src)](href)`, whose URLs tolerate one level of balanced
/// parentheses, as CommonMark does — `…/wiki/Cat_(disambiguation)` stays whole.
enum ImagePatterns {
    private static let url = #"\(((?:\([^()]*\)|[^()])+)\)"#
    private static let linked = try! NSRegularExpression(
        pattern: #"^\[!\[(.*?)\]"# + url + #"]"# + url + #"$"#
    )
    private static let plain = try! NSRegularExpression(
        pattern: #"^!\[(.*?)\]"# + url + #"$"#
    )

    /// Could this line still become image markdown?
    static func opens(_ trimmed: String) -> Bool {
        trimmed.hasPrefix("![") || trimmed.hasPrefix("[![")
    }

    /// Parses a complete image line: alt, src and href (nil when unlinked).
    /// Alt may be empty — no caption, not an empty string.
    static func match(_ trimmed: String) -> (src: String, alt: String?, href: String?)? {
        for (pattern, isLinked) in [(linked, true), (plain, false)] {
            let range = NSRange(trimmed.startIndex..., in: trimmed)
            guard let match = pattern.firstMatch(in: trimmed, range: range),
                  let alt = capture(trimmed, match, at: 1),
                  let src = capture(trimmed, match, at: 2)
            else { continue }

            let href = isLinked ? capture(trimmed, match, at: 3) : nil
            return (
                src: src,
                alt: alt.isEmpty ? nil : alt,
                href: href?.isEmpty == false ? href : nil
            )
        }
        return nil
    }

    private static func capture(
        _ string: String,
        _ match: NSTextCheckingResult,
        at index: Int
    ) -> String? {
        Range(match.range(at: index), in: string).map { String(string[$0]) }
    }
}

extension BlockSplitter {
    /// A complete image line becomes its own card right away.
    mutating func emitImage(_ parsed: (src: String, alt: String?, href: String?)) {
        append(.image(src: parsed.src, alt: parsed.alt, href: parsed.href), text: "")
    }

    /// Resolves the held line: emits its card when the pattern closed, or
    /// releases it back to the prose buffer when it turned out malformed.
    mutating func flushImage() {
        guard let held = image.held else { return }
        defer { image.release() }
        if let parsed = ImagePatterns.match(held) {
            emitImage(parsed)
        } else {
            toParagraph(held)
        }
    }
}
