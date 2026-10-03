@testable import Eigin
import Foundation
import Testing

@Suite("HTML to Markdown Converter")
struct HTMLToMarkdownConverterTests {
    // MARK: - Headings & paragraphs

    @Test func headings() {
        let md = HTMLToMarkdownConverter.convert("<h1>One</h1><h2>Two</h2><h6>Six</h6>")
        #expect(md.contains("# One"))
        #expect(md.contains("## Two"))
        #expect(md.contains("###### Six"))
    }

    @Test func emptyHeadingIsDropped() {
        let md = HTMLToMarkdownConverter.convert("<h1>  </h1><p>text</p>")
        #expect(!md.contains("#"))
    }

    @Test func paragraphsJoinAsBlocks() {
        let md = HTMLToMarkdownConverter.convert("<p>First</p><p>Second</p>")
        #expect(md == "First\n\nSecond")
    }

    // MARK: - Inline formatting

    @Test func boldItalicStrikethrough() {
        let md = HTMLToMarkdownConverter.convert(
            "<b>bold</b> <strong>s</strong> <i>it</i> <em>em</em> <del>gone</del>"
        )
        #expect(md.contains("**bold**"))
        #expect(md.contains("**s**"))
        #expect(md.contains("*it*"))
        #expect(md.contains("*em*"))
        #expect(md.contains("~~gone~~"))
    }

    @Test func emptyEmphasisProducesNothing() {
        let md = HTMLToMarkdownConverter.convert("before <b> </b> after")
        #expect(md == "before after")
    }

    @Test func kbdVarSampRenderAsCodeSpans() {
        let md = HTMLToMarkdownConverter.convert("<kbd>Ctrl</kbd> <var>x</var> <samp>out</samp>")
        #expect(md.contains("`Ctrl`"))
        #expect(md.contains("`x`"))
        #expect(md.contains("`out`"))
    }

    @Test func markdownSpecialsAreEscaped() {
        let md = HTMLToMarkdownConverter.convert("<p>2 * 3 _ 4 [x] \\ y</p>")
        #expect(md.contains(#"2 \* 3 \_ 4 \[x\] \\ y"#))
    }

    @Test func listItemNumbersAreNotEscaped() {
        let md = HTMLToMarkdownConverter.convert("<p>Step 1. done and 0.4 grams</p>")
        #expect(md == "Step 1. done and 0.4 grams")
    }

    // MARK: - Links

    @Test func linkWithAbsoluteHREF() {
        let md = HTMLToMarkdownConverter.convert("<a href=\"https://eigin.ai\">Eigin</a>")
        #expect(md == "[Eigin](https://eigin.ai)")
    }

    @Test func relativeLinkResolvesAgainstBaseURL() throws {
        let md = try HTMLToMarkdownConverter.convert(
            "<a href=\"/docs/page\">Docs</a>",
            baseURL: #require(URL(string: "https://example.com/base/"))
        )
        #expect(md == "[Docs](https://example.com/docs/page)")
    }

    @Test func fragmentLinkKeepsTextDropsHREF() {
        let md = HTMLToMarkdownConverter.convert("<a href=\"#section\">jump</a>")
        #expect(md == "jump")
    }

    @Test func javascriptHrefIsDropped() {
        let md = HTMLToMarkdownConverter.convert("<a href=\"javascript:alert(1)\">click</a>")
        #expect(md == "click")
    }

    @Test func hrefWithParensIsEscaped() {
        let md = HTMLToMarkdownConverter.convert("<a href=\"https://x.com/a(b)\">link</a>")
        #expect(md == "[link](https://x.com/a%28b%29)")
    }

    // MARK: - Images

    @Test func imageRendersAltAndTitle() throws {
        let md = try HTMLToMarkdownConverter.convert(
            "<img src=\"/pic.png\" alt=\"A cat\" title=\"meow\">",
            baseURL: #require(URL(string: "https://example.com/"))
        )
        #expect(md == "![A cat](https://example.com/pic.png \"meow\")")
    }

    // MARK: - Lists

    @Test func unorderedList() {
        let md = HTMLToMarkdownConverter.convert("<ul><li>one</li><li>two</li></ul>")
        #expect(md == "- one\n- two")
    }

    @Test func orderedListHonorsStartAttribute() {
        let md = HTMLToMarkdownConverter.convert("<ol start=\"10\"><li>a</li><li>b</li></ol>")
        #expect(md == "10. a\n11. b")
    }

    @Test func nestedListIndents() {
        let md = HTMLToMarkdownConverter.convert(
            "<ul><li>outer<ul><li>inner</li></ul></li></ul>"
        )
        #expect(md.contains("- outer"))
        #expect(md.contains("  - inner"))
    }

    @Test func emptyListItemsAreDropped() {
        let md = HTMLToMarkdownConverter.convert("<ul><li></li><li>kept</li><li>  </li></ul>")
        #expect(md == "- kept")
    }

    @Test func taskListMarkers() {
        let md = HTMLToMarkdownConverter.convert(
            """
            <ul>
              <li><input type="checkbox" checked>done</li>
              <li><input type="checkbox">todo</li>
            </ul>
            """
        )
        #expect(md.contains("[x] done"))
        #expect(md.contains("[ ] todo"))
    }

    // MARK: - Code & blockquote

    @Test func codeFenceWithLanguage() {
        let md = HTMLToMarkdownConverter.convert(
            "<pre><code class=\"language-swift\">let x = 1</code></pre>"
        )
        #expect(md == "```swift\nlet x = 1\n```")
    }

    @Test func blockquotePrefixesLines() {
        let md = HTMLToMarkdownConverter.convert("<blockquote><p>line</p><p>two</p></blockquote>")
        #expect(md == "> line\n>\n> two")
    }

    @Test func hrRendersDivider() {
        let md = HTMLToMarkdownConverter.convert("<p>above</p><hr><p>below</p>")
        #expect(md == "above\n\n---\n\nbelow")
    }

    // MARK: - Tables

    @Test func tableRendersGFMStyle() {
        let md = HTMLToMarkdownConverter.convert(
            "<table><tr><th>A</th><th>B</th></tr><tr><td>1</td><td>2</td></tr></table>"
        )
        #expect(md.contains("| A | B |"))
        #expect(md.contains("| --- | --- |"))
        #expect(md.contains("| 1 | 2 |"))
    }

    @Test func cellWithPipeIsEscaped() {
        let md = HTMLToMarkdownConverter.convert(
            "<table><tr><td>a|b</td></tr></table>"
        )
        #expect(md.contains(#"a\|b"#))
    }

    // MARK: - Removal & safety

    @Test func dangerousElementsAreRemoved() {
        let html = """
        <script>alert('x')</script><style>.x{}</style><noscript>n</noscript>
        <iframe src="https://evil.example"></iframe><form><input type="text"></form>
        <p>kept</p>
        """
        let md = HTMLToMarkdownConverter.convert(html)
        #expect(!md.contains("alert"))
        #expect(!md.contains(".x"))
        #expect(!md.contains("evil.example"))
        #expect(md.contains("kept"))
    }

    @Test func entitiesAreDecoded() {
        let md = HTMLToMarkdownConverter.convert("<p>5 &lt; 10 &amp; &nbsp;&quot;q&quot;</p>")
        #expect(md.contains("5 < 10 &"))
        #expect(md.contains(#""q""#))
    }

    @Test func unclosedHeadingSplitsSwallowedBlocks() {
        // Tag soup: an unclosed <h1> makes the parser nest paragraphs inside
        // it — the heading must not swallow them into one line.
        let md = HTMLToMarkdownConverter.convert("<article><h1>Title\n<p>one\n<p>two</article>")
        #expect(md.contains("# Title"))
        #expect(md.contains("\n\none"))
        #expect(md.contains("\n\ntwo"))
    }

    @Test func siteHeaderOutsideArticleIsChrome() {
        let md = HTMLToMarkdownConverter.convert(
            """
            <header><a href="/signin">Sign in</a></header>
            <article><header><h1>Real headline</h1></header><p>body</p></article>
            """
        )
        #expect(!md.contains("Sign in"))
        #expect(md.contains("# Real headline"))
    }

    @Test func malformedHTMLDoesNotCrash() {
        let md = HTMLToMarkdownConverter.convert("<p><b>broken<ul><li>item")
        #expect(md.contains("broken"))
        #expect(md.contains("item"))
    }

    @Test func emptyInputGivesEmptyOutput() {
        #expect(HTMLToMarkdownConverter.convert("") == "")
    }

    // MARK: - Chrome filtering & navigation links

    @Test func navAsideFooterRemovedFromBody() {
        let md = HTMLToMarkdownConverter.convert(
            """
            <nav><a href="/a">Nav1</a></nav>
            <article><p>content</p></article>
            <footer><a href="/b">Footer1</a></footer>
            """
        )
        #expect(md.contains("content"))
        #expect(!md.contains("Nav1"))
        #expect(!md.contains("Footer1"))
    }

    @Test func chromeClassTokensAreFiltered() {
        let md = HTMLToMarkdownConverter.convert(
            """
            <div class="cookie-banner">Accept cookies</div>
            <div class="mega-menu"><a href="/menu">Menu item</a></div>
            <p>kept</p>
            """
        )
        #expect(!md.contains("Accept cookies"))
        #expect(!md.contains("Menu item"))
        #expect(md.contains("kept"))
    }

    @Test func contentContainersSurviveChromeClasses() {
        // Real-world pages put content inside <main class="modal__content">.
        let md = HTMLToMarkdownConverter.convert(
            """
            <main class="modal__content"><h1>Title</h1><p>body</p></main>
            """
        )
        #expect(md.contains("# Title"))
        #expect(md.contains("body"))
    }

    @Test func ancestorsOfContentAreKept() {
        // A content wrapper whose class mentions "sidebar" must survive —
        // dropping it would drop the page.
        let md = HTMLToMarkdownConverter.convert(
            """
            <div class="content-sidebar-wrap">
                <main><p>recipe text</p></main>
            </div>
            """
        )
        #expect(md.contains("recipe text"))
    }

    @Test func hiddenElementsAreDropped() {
        let md = HTMLToMarkdownConverter.convert(
            """
            <div aria-hidden="true">ghost</div>
            <div style="display:none">invisible</div>
            <p>visible</p>
            """
        )
        #expect(!md.contains("ghost"))
        #expect(!md.contains("invisible"))
        #expect(md.contains("visible"))
    }

    @Test func navigationLinksPreservedAtTop() throws {
        let md = try HTMLToMarkdownConverter.convert(
            """
            <nav>
                <a href="/docs">Article index</a>
                <a href="#top">Skip to main content</a>
            </nav>
            <p>Content mentions https://example.com/docs</p>
            """,
            baseURL: #require(URL(string: "https://example.com/page"))
        )
        // Navigation block first (so truncation keeps it).
        #expect(md.hasPrefix("Site navigation"))
        #expect(md.contains("Article index: https://example.com/docs"))
        // Same-page skip links add nothing — dropped.
        #expect(!md.contains("Skip to main content"))
    }

    @Test func crossSiteNavLinksAreNotHarvested() throws {
        let md = try HTMLToMarkdownConverter.convert(
            """
            <nav>
                <a href="https://other-site.com/page">Other site</a>
                <a href="https://example.com/page">Same site</a>
            </nav>
            <p>body</p>
            """,
            baseURL: #require(URL(string: "https://example.com/page"))
        )
        #expect(md.contains("Same site"))
        #expect(!md.contains("Other site: "))
    }

    @Test func navLinksAlreadyInBodyAreNotRepeated() throws {
        let md = try HTMLToMarkdownConverter.convert(
            """
            <nav><a href="/about">About us</a></nav>
            <p>Read <a href="/about">About us</a></p>
            """,
            baseURL: #require(URL(string: "https://example.com/"))
        )
        // The body link keeps its markdown form; the nav block omits it.
        #expect(md.contains("[About us](https://example.com/about)"))
        let navCount = md.components(separatedBy: "About us: ").count - 1
        #expect(navCount == 0, "nav block repeats a body link: \(md)")
    }
}
