import Foundation
import SwiftSoup

/// Converts HTML to compact Markdown (CommonMark core + GFM tables).
///
/// Parsing is delegated to SwiftSoup, which tolerates malformed markup and
/// decodes HTML entities. Rendering rules are fixed — no plugin system.
enum HTMLToMarkdownConverter {
    /// Elements removed from the tree before rendering. Doubles as safety
    /// sanitization: no executable or interactive content reaches the output.
    static let removedElements: Set<String> = [
        "script", "style", "noscript", "head", "template",
        "iframe", "svg", "form", "button", "select",
        "nav", "footer", "aside",
    ]

    /// ARIA roles that mark site chrome rather than content.
    static let removedRoles: Set<String> = [
        "navigation", "banner", "complementary", "contentinfo",
        "search", "menu", "menubar", "dialog", "alertdialog",
    ]

    /// Class/id tokens that mark site chrome (cookie banners, menus, promos).
    /// Matched as whole tokens to limit false positives inside longer words.
    static let boilerplateTokens: Set<String> = [
        "navbar", "nav", "menu", "navigation", "sidebar", "breadcrumb",
        "breadcrumbs", "cookie", "cookies", "newsletter", "subscribe",
        "promo", "advert", "advertisement", "sponsor", "skip",
        "masthead", "share", "sharing", "popup", "modal",
    ]

    /// Link-text fragments that never carry navigation value.
    static let navigationStopTexts: Set<String> = [
        "sign in", "sign up", "log in", "login", "log out", "logout",
        "search", "skip to content", "skip to main content", "subscribe",
        "learn more",
        "register", "menu", "settings", "cookie", "accept", "manage",
    ]

    /// Maximum links listed in the site-navigation block.
    static let maxNavigationLinks = 30

    /// Convert HTML to Markdown. `baseURL` resolves relative link and image
    /// URLs. Navigation chrome is stripped from the body and its same-site
    /// links are preserved in a compact block at the top — it must survive
    /// truncation, which cuts from the end.
    static func convert(_ html: String, baseURL: URL? = nil) -> String {
        guard let document = try? SwiftSoup.parse(html) else { return "" }
        guard let body = document.body() else { return "" }

        var harvestedLinks: [String: String] = [:] // href → text (first seen)
        removeElements(from: body, baseURL: baseURL, links: &harvestedLinks)

        let blocks = Renderer(baseURL: baseURL).renderBlocks(body.getChildNodes())
        let markdown = Whitespace.joinBlocks(blocks)
        if let navigation = navigationBlock(harvestedLinks, in: markdown) {
            return navigation + "\n\n" + markdown
        }
        return markdown
    }

    // MARK: - Chrome removal & navigation harvest

    /// Containers that must always render — pages park the actual content
    /// inside them even when their class names look like chrome.
    static let contentContainers: Set<String> = ["main", "article"]

    static func removeElements(
        from node: Node,
        baseURL: URL?,
        links: inout [String: String]
    ) {
        for element in node.getChildNodes() where isElementNode(element) {
            if isChrome(element), !isContentContainer(element),
               !containsContentContainer(element)
            {
                harvestLinks(from: element, baseURL: baseURL, links: &links)
                try? element.parent()?.removeChild(element)
                continue
            }
            removeElements(from: element, baseURL: baseURL, links: &links)
        }
    }

    /// Site chrome to drop — everything ``isBoilerplate`` catches, plus site
    /// headers. `<header>` outside an article is chrome (logins, menus);
    /// inside an article it holds the headline and must render.
    static func isChrome(_ node: Node) -> Bool {
        guard let element = node as? Element else { return false }
        if element.tagName().lowercased() == "header" {
            return !hasArticleAncestor(element)
        }
        return isBoilerplate(node)
    }

    private static func hasArticleAncestor(_ element: Element) -> Bool {
        var parent = element.parent()
        var depth = 0
        while let node = parent, depth < 10 {
            if let ancestor = node as? Element, ancestor.tagName().lowercased() == "article" {
                return true
            }
            parent = node.parent()
            depth += 1
        }
        return false
    }

    private static func containsContentContainer(_ node: Node, depth: Int = 6) -> Bool {
        guard depth > 0 else { return false }
        for child in node.getChildNodes() where isElementNode(child) {
            if isContentContainer(child) || containsContentContainer(child, depth: depth - 1) {
                return true
            }
        }
        return false
    }

    private static func isContentContainer(_ node: Node) -> Bool {
        guard let element = node as? Element else { return false }
        return contentContainers.contains(element.tagName().lowercased())
    }

    /// Site chrome: chrome tags, chrome ARIA roles, chrome class/id tokens,
    /// and anything explicitly hidden.
    static func isBoilerplate(_ node: Node) -> Bool {
        guard let element = node as? Element else { return false }
        if removedElements.contains(element.tagName().lowercased()) {
            return true
        }
        let role = ((try? element.attr("role")) ?? "").lowercased()
        if removedRoles.contains(role) {
            return true
        }
        for attribute in ["aria-hidden", "hidden"] {
            if !((try? element.attr(attribute)) ?? "").isEmpty {
                return true
            }
        }
        let style = ((try? element.attr("style")) ?? "")
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
        if style.contains("display:none") || style.contains("visibility:hidden") {
            return true
        }
        for attribute in ["class", "id"] {
            let value = ((try? element.attr(attribute)) ?? "").lowercased()
            guard !value.isEmpty else { continue }
            let tokens = value.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            if tokens.contains(where: { boilerplateTokens.contains(String($0)) }) {
                return true
            }
        }
        return false
    }

    static func isElementNode(_ node: Node) -> Bool {
        !node.nodeName().hasPrefix("#")
    }

    /// Collect same-site links from removed chrome so the agent can still
    /// discover other pages on the site.
    static func harvestLinks(
        from node: Node,
        baseURL: URL?,
        links: inout [String: String]
    ) {
        guard links.count < maxNavigationLinks * 4 else { return }
        guard let element = node as? Element else {
            for child in node.getChildNodes() {
                harvestLinks(from: child, baseURL: baseURL, links: &links)
            }
            return
        }

        if element.tagName().lowercased() == "a" {
            let raw = ((try? element.attr("href")) ?? "").trimmingCharacters(in: .whitespaces)
            if isNavigable(raw, baseURL: baseURL) {
                let text = ((try? element.text()) ?? "")
                    .split(separator: "\n")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                let resolved = URL(string: raw, relativeTo: baseURL)?
                    .absoluteString ?? raw
                if !text.isEmpty, isUsefulLinkText(text), links[resolved] == nil {
                    links[resolved] = text
                }
            }
            return
        }

        for child in element.getChildNodes() {
            harvestLinks(from: child, baseURL: baseURL, links: &links)
        }
    }

    /// Only same-site http(s) URLs — cross-host links are social/search noise;
    /// without a base URL, any absolute http(s) link counts.
    static func isNavigable(_ raw: String, baseURL: URL?) -> Bool {
        guard !raw.isEmpty,
              !raw.lowercased().hasPrefix("javascript:"),
              !raw.hasPrefix("#")
        else { return false }
        guard let target = URL(string: raw, relativeTo: baseURL) else { return false }
        guard target.scheme == "http" || target.scheme == "https" else { return false }
        guard let baseURL else { return true }
        guard let targetHost = target.host, let pageHost = baseURL.host else {
            return false
        }
        return targetHost == pageHost
            || targetHost == "www." + pageHost
            || pageHost == "www." + targetHost
    }

    static func isUsefulLinkText(_ text: String) -> Bool {
        let lower = text.lowercased()
        for stop in navigationStopTexts where lower.contains(stop) {
            return false
        }
        return true
    }

    /// Compact single-line block of same-site links not already in the body.
    static func navigationBlock(
        _ links: [String: String],
        in markdown: String
    ) -> String? {
        var entries: [String] = []
        for (href, text) in links.sorted(by: { $0.value < $1.value }) {
            guard entries.count < maxNavigationLinks else { break }
            // Skip URLs already linked in the body markdown.
            if markdown.contains("](\(href))") { continue }
            let label = text.count > 60 ? String(text.prefix(57)) + "…" : text
            entries.append("\(label): \(href)")
        }
        guard !entries.isEmpty else { return nil }
        return "Site navigation: " + entries.joined(separator: " · ")
    }
}
