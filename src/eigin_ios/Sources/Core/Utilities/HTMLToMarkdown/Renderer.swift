import Foundation
import SwiftSoup

/// Walks the DOM and produces Markdown blocks (paragraphs, headings, lists…).
struct Renderer {
    let baseURL: URL?

    /// Raw text content of a node, or "" for non-text nodes.
    func textContent(of node: Node) -> String {
        (node as? TextNode)?.getWholeText() ?? ""
    }

    /// Render a run of sibling nodes as a list of block strings.
    func renderBlocks(_ nodes: [Node]) -> [String] {
        var blocks: [String] = []
        var pendingText: [String] = []

        for node in nodes {
            if isTextNode(node) {
                let text = textContent(of: node)
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    pendingText.append(text)
                }
                continue
            }
            guard let element = node as? Element else { continue }
            // Inline containers that hold block content (span > table) must
            // render as containers, or the tables flatten to plain text.
            if isBlockElement(element) || Renderer.containsBlockElement(element) {
                if !pendingText.isEmpty {
                    blocks.append(Whitespace.collapse(pendingText.joined(separator: " ")))
                    pendingText = []
                }
                if let block = renderBlock(element) {
                    blocks.append(block)
                }
            } else {
                // Inline content floating directly in a block container.
                if let inline = renderInlineNode(element) {
                    pendingText.append(inline)
                }
            }
        }

        if !pendingText.isEmpty {
            blocks.append(Whitespace.collapse(pendingText.joined(separator: " ")))
        }
        return blocks
    }

    /// Render one block-level element, or nil if it produces no output.
    func renderBlock(_ element: Element) -> String? {
        switch element.tagName().lowercased() {
        case "h1", "h2", "h3", "h4", "h5", "h6":
            let level = Int(element.tagName().suffix(1)) ?? 1
            // Tag soup can leave a heading holding paragraphs — render the
            // heading marker on the first block and keep the rest separate.
            var childBlocks = renderBlocks(element.getChildNodes())
            guard !childBlocks.isEmpty else { return nil }
            childBlocks[0] = String(repeating: "#", count: min(level, 6)) + " " + childBlocks[0]
            return childBlocks.joined(separator: "\n\n")

        case "p":
            let text = renderInlineParagraph(element)
            return text.isEmpty ? nil : text

        case "ul", "ol":
            return renderList(element, ordered: element.tagName() == "ol", indent: "")

        case "blockquote":
            let inner = renderBlocks(element.getChildNodes())
            guard !inner.isEmpty else { return nil }
            return inner
                .joined(separator: "\n\n")
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { $0.isEmpty ? ">" : "> " + $0 }
                .joined(separator: "\n")

        case "pre":
            return renderPreformatted(element)

        case "table":
            return TableRenderer(baseURL: baseURL).render(element)

        case "hr":
            return "---"

        case "dl":
            return renderDefinitionList(element)

        case "br":
            return nil

        default:
            // Containers (div, article, section, header, figure…) render children.
            let inner = renderBlocks(element.getChildNodes())
            return inner.isEmpty ? nil : inner.joined(separator: "\n\n")
        }
    }

    // MARK: - Lists

    func renderList(_ list: Element, ordered: Bool, indent: String) -> String {
        var lines: [String] = []
        // <ol start="10"> keeps source numbering.
        var index = ordered ? (Int((try? list.attr("start")) ?? "") ?? 1) : 1

        for child in list.getChildNodes() {
            guard let li = child as? Element, li.tagName().lowercased() == "li" else { continue }

            var marker = ordered ? "\(index). " : "- "
            let checkbox = firstCheckbox(li)
            // Site-drawn box glyphs mean the checkbox is decorative — skip the
            // task marker to avoid "- [ ] ▢ text".
            let decorativeBox = hasBoxGlyph(li)
            if checkbox != nil, !decorativeBox {
                marker += isChecked(checkbox!) ? "[x] " : "[ ] "
            }
            index += 1

            let (content, nested) = renderListItem(li, indent: indent + "  ")

            // Menu items with no content are pure noise — drop them, but keep
            // their nested lists (promoted as-is when the marker line is empty).
            if content.isEmpty {
                if !nested.isEmpty {
                    lines.append(nested)
                }
                continue
            }

            let itemLines = (marker + content).split(
                separator: "\n",
                omittingEmptySubsequences: false
            )
            lines.append(itemLines.enumerated().map { position, line in
                position == 0 ? indent + line : indent + "  " + line
            }.joined(separator: "\n"))

            if !nested.isEmpty {
                lines.append(nested)
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Render one `<li>`: inline content plus nested blocks that keep list indentation.
    func renderListItem(_ li: Element, indent: String) -> (content: String, nested: String) {
        var inlineParts: [String] = []
        var nestedBlocks: [String] = []

        for child in li.getChildNodes() {
            if isTextNode(child) {
                let text = textContent(of: child)
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    inlineParts.append(text)
                }
            } else if let element = child as? Element {
                if element.tagName().lowercased() == "ul" || element.tagName()
                    .lowercased() == "ol"
                {
                    let nested = renderList(
                        element,
                        ordered: element.tagName() == "ol",
                        indent: indent + "  "
                    )
                    if !nested.isEmpty { nestedBlocks.append(nested) }
                } else if isBlockElement(element), element.tagName().lowercased() != "p" {
                    // Route through renderBlock so tables, code fences, etc.
                    // keep their dedicated rendering inside list items.
                    if let block = renderBlock(element) {
                        nestedBlocks.append(block)
                    }
                } else if isBlockElement(element) {
                    // A <p> inside a list item joins the item's primary line.
                    inlineParts.append(renderInlineParagraph(element))
                } else if let inline = renderInlineNode(element) {
                    inlineParts.append(inline)
                }
            }
        }

        let content = Whitespace.collapse(inlineParts.joined(separator: " "))
        return (content, nestedBlocks.joined(separator: "\n"))
    }

    func isTaskItem(_ li: Element) -> Bool {
        firstCheckbox(li) != nil
    }

    func isChecked(_ li: Element) -> Bool {
        guard let checkbox = firstCheckbox(li) else { return false }
        // Boolean attribute serializes with an empty value when present.
        guard checkbox.hasAttr("checked") else { return false }
        let value = (try? checkbox.attr("checked")) ?? ""
        return value.lowercased() != "false"
    }

    func hasBoxGlyph(_ li: Element) -> Bool {
        let text = (try? li.text()) ?? ""
        let glyphs: Set<Character> = ["▢", "☐", "☑", "✓", "✔"]
        return text.contains(where: glyphs.contains)
    }

    private func firstCheckbox(_ li: Element) -> Element? {
        (try? li.getElementsByTag("input"))?.array().first { element in
            (try? element.attr("type"))?.lowercased() == "checkbox"
        }
    }

    // MARK: - Preformatted & definition lists

    func renderPreformatted(_ pre: Element) -> String? {
        let raw = (try? pre.text()) ?? ""
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let language = preCodeLanguage(pre)
        let fence = String(repeating: "`", count: max(3, longestBacktickRun(in: trimmed) + 1))
        return fence + (language.map { $0 } ?? "") + "\n" + trimmed + "\n" + fence
    }

    func preCodeLanguage(_ pre: Element) -> String? {
        guard let code = (try? pre.getElementsByTag("code"))?.array().first else { return nil }
        let classes = (try? code.attr("class")) ?? ""
        for token in classes.split(separator: " ") {
            if token.hasPrefix("language-") || token.hasPrefix("lang-") {
                return String(token.drop { $0 != "-" }.dropFirst())
            }
        }
        return nil
    }

    func longestBacktickRun(in text: String) -> Int {
        var longest = 0
        var current = 0
        for character in text {
            if character == "`" {
                current += 1
                longest = max(longest, current)
            } else {
                current = 0
            }
        }
        return longest
    }

    func renderDefinitionList(_ dl: Element) -> String? {
        var blocks: [String] = []

        for child in dl.getChildNodes() {
            guard let element = child as? Element else { continue }
            switch element.tagName().lowercased() {
            case "dt":
                let text = Whitespace.collapse(renderInlineChildren(element))
                if !text.isEmpty { blocks.append("**" + text + "**") }
            case "dd":
                let text = renderInlineParagraph(element)
                if !text.isEmpty { blocks.append(": " + text) }
            default:
                break
            }
        }
        return blocks.isEmpty ? nil : blocks.joined(separator: "\n")
    }
}
