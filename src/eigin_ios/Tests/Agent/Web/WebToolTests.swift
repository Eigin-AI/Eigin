@testable import Eigin
import Foundation
import Testing

@Suite("Web Tools")
struct WebToolTests {
    // MARK: - HTMLSanitizer.sanitize()

    @Test func sanitizeStripsScriptTags() {
        let html = "<p>Hello</p><script>alert('xss')</script><p>World</p>"
        let (text, _) = HTMLSanitizer.sanitize(html)
        #expect(!text.contains("alert"))
        #expect(text.contains("Hello"))
        #expect(text.contains("World"))
    }

    @Test func sanitizeStripsStyleTags() {
        let html = "<style>body { color: red }</style><p>Content</p>"
        let (text, _) = HTMLSanitizer.sanitize(html)
        #expect(!text.contains("color"))
        #expect(text.contains("Content"))
    }

    @Test func sanitizeStripsNoscriptTags() {
        let html = "<noscript>Enable JS</noscript><p>Visible</p>"
        let (text, _) = HTMLSanitizer.sanitize(html)
        #expect(!text.contains("Enable JS"))
        #expect(text.contains("Visible"))
    }

    @Test func sanitizeStripsHeadBlock() {
        let html = "<head><title>Page</title><meta charset='utf-8'></head><body>Body text</body>"
        let (text, _) = HTMLSanitizer.sanitize(html)
        #expect(!text.contains("<title>"))
        #expect(text.contains("Body text"))
    }

    @Test func sanitizeRemovesHTMLTags() {
        let html = "<div><span class=\"bold\">Hello</span> <a href=\"#\">link</a></div>"
        let (text, _) = HTMLSanitizer.sanitize(html)
        #expect(!text.contains("<"))
        #expect(!text.contains(">"))
        #expect(text.contains("Hello"))
        #expect(text.contains("link"))
    }

    @Test func sanitizeDecodesNamedEntities() {
        let html = "5 &lt; 10 &amp; 10 &gt; 5 &quot;quoted&quot; &#39;apos&#39;"
        let (text, _) = HTMLSanitizer.sanitize(html)
        #expect(text.contains("5 < 10 & 10 > 5"))
        #expect(text.contains("\"quoted\""))
        #expect(text.contains("'apos'"))
    }

    @Test func sanitizeDecodesNumericEntities() {
        let html = "&#65;&#66;&#67; &#x41;&#x42;&#x43;"
        let (text, _) = HTMLSanitizer.sanitize(html)
        #expect(text.contains("ABC"))
        // Both decimal and hex should decode to the same characters
        #expect(text == "ABC ABC")
    }

    @Test func sanitizeCollapsesWhitespace() {
        let html = "Hello    world\n\n\n\n\nNew section"
        let (text, _) = HTMLSanitizer.sanitize(html)
        #expect(text == "Hello world\nNew section")
    }

    @Test func sanitizeCollapsesMixedWhitespaceWithNewlines() {
        let html = "Line 1\n\n  \n\n\n \n Line 2"
        let (text, _) = HTMLSanitizer.sanitize(html)
        #expect(text == "Line 1\nLine 2")
    }

    @Test func sanitizeTruncatesLongContent() {
        let long = String(repeating: "A", count: 25000)
        let (text, warnings) = HTMLSanitizer.sanitize(long)
        #expect(text.count == HTMLSanitizer.maxOutputLength)
        #expect(warnings.count == 1)
        #expect(warnings[0].contains("truncated"))
    }

    @Test func sanitizeHandlesEmptyInput() {
        let (text, warnings) = HTMLSanitizer.sanitize("")
        #expect(text.isEmpty)
        #expect(warnings.isEmpty)
    }

    @Test func sanitizeReplacesBlockTagsWithNewlines() {
        let html = "<p>Para 1</p><p>Para 2</p><br><div>Div</div>"
        let (text, _) = HTMLSanitizer.sanitize(html)
        #expect(text.contains("Para 1\n"))
        #expect(text.contains("Para 2"))
    }

    // MARK: - Tool Metadata

    @Test func webSearchToolMetadata() {
        let tool = WebSearchTool()
        #expect(tool.name == "web_search")
        #expect(tool.capabilities == [WebSearchTool.capability])
        #expect(tool.category == .external)
        #expect(tool.defaultPermissionLevel == .ask)
    }

    @Test func webFetchToolMetadata() {
        let tool = WebFetchTool()
        #expect(tool.name == "web_fetch")
        #expect(tool.capabilities == [WebFetchTool.capability])
        #expect(tool.category == .external)
        #expect(tool.defaultPermissionLevel == .ask)
    }
}
