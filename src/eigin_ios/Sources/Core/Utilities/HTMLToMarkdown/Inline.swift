import Foundation
import SwiftSoup

/// Inline rendering: links, emphasis, code spans, images, line breaks.
extension Renderer {
    /// Render an element's children as inline content (one flowing string).
    func renderInlineChildren(_ element: Element) -> String {
        var parts: [String] = []

        for child in element.getChildNodes() {
            if isTextNode(child) {
                parts.append(Escaping.text(textContent(of: child)))
            } else if let inlineChild = child as? Element,
                      let inline = renderInlineNode(inlineChild)
            {
                parts.append(inline)
            }
        }
        return parts.joined(separator: "")
    }

    /// Render an element's children as a single-line paragraph.
    /// Block children flatten into the same line; `<br>` becomes a space.
    func renderInlineParagraph(_ element: Element) -> String {
        Whitespace.collapse(renderInlineChildren(element))
    }

    /// Render one inline element. Returns nil for elements producing no output.
    func renderInlineNode(_ element: Element) -> String? {
        switch element.tagName().lowercased() {
        case "a":
            return renderLink(element)
        case "strong", "b":
            let text = Whitespace.collapse(renderInlineChildren(element))
            return text.trimmingCharacters(in: .whitespaces).isEmpty ? nil : "**" + text
                .trimmingCharacters(in: .whitespaces) + "**"
        case "em", "i":
            let text = Whitespace.collapse(renderInlineChildren(element))
            return text.trimmingCharacters(in: .whitespaces).isEmpty ? nil : "*" + text
                .trimmingCharacters(in: .whitespaces) + "*"
        case "code", "var", "samp", "kbd", "tt":
            let text = (try? element.text()) ?? ""
            return text.trimmingCharacters(in: .whitespaces).isEmpty ? nil : Escaping.codeSpan(text)
        case "del", "s", "strike":
            let text = Whitespace.collapse(renderInlineChildren(element))
            return text.trimmingCharacters(in: .whitespaces).isEmpty ? nil : "~~" + text
                .trimmingCharacters(in: .whitespaces) + "~~"
        case "img":
            return renderImage(element)
        case "br":
            return "\n"
        case "span", "small", "sup", "sub", "abbr", "time", "font", "label", "u", "q", "cite",
             "mark":
            return renderInlineChildren(element)
        case "hr":
            return nil
        default:
            if isBlockElement(element) {
                // A block inside inline flow (e.g. <div> inside <p>): hard break.
                let inline = renderInlineChildren(element)
                return inline.isEmpty ? nil : "\n" + inline
            }
            return renderInlineChildren(element)
        }
    }

    func renderLink(_ element: Element) -> String? {
        let raw = ((try? element.attr("href")) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Same-page fragment links ("") contribute nothing actionable.
        // "Skip to content" style links are pure chrome — drop entirely.
        if raw.hasPrefix("#") {
            let text = Whitespace.collapse(renderInlineChildren(element))
            if text.isEmpty || !HTMLToMarkdownConverter.isUsefulLinkText(text) { return nil }
            return text
        }
        guard let href = resolveURL(raw, baseURL: baseURL) else {
            // No usable href — keep the text only.
            let text = Whitespace.collapse(renderInlineChildren(element))
            return text.isEmpty ? nil : text
        }

        let text = Whitespace.collapse(renderInlineChildren(element))
        if text.isEmpty || text == href {
            // Bare or self-referential link: keep the URL once.
            return href
        }
        return "[" + text + "](" + Escaping.href(href) + ")"
    }

    func renderImage(_ element: Element) -> String? {
        let src = resolveURL((try? element.attr("src")) ?? "", baseURL: baseURL)
        guard let src else { return nil }
        let alt = Whitespace.collapse((try? element.attr("alt")) ?? "").replacingOccurrences(
            of: "[",
            with: "\\["
        )
        .replacingOccurrences(of: "]", with: "\\]")
        .replacingOccurrences(of: "(", with: "\\(")
        .replacingOccurrences(of: ")", with: "\\)")
        var suffix = ""
        let title = ((try? element.attr("title")) ?? "").trimmingCharacters(in: .whitespaces)
        if !title.isEmpty {
            suffix = " \"" + title.replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }
        return "![" + alt + "](" + Escaping.href(src) + suffix + ")"
    }

    /// Resolve a possibly-relative URL against the page URL. Returns nil for
    /// empty or javascript: URLs; without a base URL the raw value is kept.
    func resolveURL(_ raw: String, baseURL: URL?) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.lowercased().hasPrefix("javascript:") else { return nil }
        if let base = baseURL, let resolved = URL(string: trimmed, relativeTo: base) {
            return resolved.absoluteString
        }
        return trimmed
    }
}

/// Element classification for block vs inline dispatch.
/// Unknown tags default to inline (transparent), so lightweight markup still
/// flows, while known containers split output into blocks.
func isBlockElement(_ element: Element) -> Bool {
    Renderer.blockElements.contains(element.tagName().lowercased())
}

func isTextNode(_ node: Node) -> Bool {
    node.nodeName().hasPrefix("#text") || node is TextNode
}

extension Renderer {
    /// True if the element or a descendant (bounded depth) is a block element.
    static func containsBlockElement(_ element: Element, depth: Int = 8) -> Bool {
        guard depth > 0 else { return false }
        for child in element.getChildNodes() {
            guard let childElement = child as? Element else { continue }
            if isBlockElement(childElement) ||
                containsBlockElement(childElement, depth: depth - 1)
            {
                return true
            }
        }
        return false
    }

    static let blockElements: Set<String> = [
        "address", "article", "aside", "blockquote", "body", "canvas", "caption",
        "center", "dd", "details", "dialog", "div", "dl", "dt", "fieldset",
        "figcaption", "figure", "footer", "form", "h1", "h2", "h3", "h4", "h5",
        "h6", "header", "hgroup", "hr", "html", "legend", "li", "main", "menu",
        "nav", "ol", "p", "pre", "section", "summary", "table", "tbody",
        "tfoot", "thead", "tr", "td", "th", "ul",
    ]
}
