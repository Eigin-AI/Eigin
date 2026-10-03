@testable import Eigin
import Foundation
import Testing

/// Layout fixtures: synthetic pages modeled on real-world layouts (news
/// article, docs site, recipe, repo page, JS-chrome-heavy portal). Real
/// third-party pages can't be committed, so these mirror the markup patterns
/// that matter: chrome structure, class-name soup, checkbox lists, tables,
/// code fences, relative links.
@Suite("HTML to Markdown Fixtures")
struct HTMLToMarkdownFixtureTests {
    private final class BundleToken {}

    /// (fixture, source URL, markers that must survive conversion)
    private static let fixtures: [(name: String, url: String, markers: [String])] = [
        (
            "article", "https://news.example.org/articles/city-floods",
            ["# Rivers burst their banks", "Mara Jensen", "[flooding]", "Site navigation"]
        ),
        (
            "docs", "https://docs.example.com/guides/fetch",
            ["# fetch()", "```javascript", "| Option | Default |", "Site navigation"]
        ),
        (
            "recipe", "https://opskrifter.example.dk/rodfrugtlasagne",
            ["Ingredienser", "Fremgangsmåde", "▢", "| Kalorier | Kulhydrater |", "Site navigation"]
        ),
        (
            "repo", "https://code.example.com/scinfu/swiftsoup",
            ["```swift", "| Platform | Status |", "Site navigation"]
        ),
        (
            "portal", "https://portal.example.com/",
            ["# Welcome to your portal", "This week's report", "Site navigation"]
        ),
    ]

    @Test("Layout pages convert to structured markdown with chrome filtered", arguments: fixtures)
    func fixtureConversion(_ fixture: (name: String, url: String, markers: [String])) throws {
        let html = try loadFixture(fixture.name)
        let elapsed = try ContinuousClock().measure {
            _ = HTMLToMarkdownConverter.convert(html, baseURL: URL(string: fixture.url))
        }
        let markdown = HTMLToMarkdownConverter.convert(html, baseURL: URL(string: fixture.url))

        // Conversion is fast — slower means a pathological parse loop.
        #expect(elapsed < .seconds(1), "\(fixture.name) took \(elapsed)")

        // Content structure survives.
        for marker in fixture.markers {
            #expect(markdown.contains(marker), "\(fixture.name): missing marker \(marker)")
        }

        // Chrome content is gone. Footer nav links legitimately survive in
        // the harvested Site navigation block, so only banner/promo/overlay
        // text and sign-in links are asserted.
        #expect(!markdown.contains("We use cookies"), "\(fixture.name): cookie banner leaked")
        #expect(!markdown.contains("Accept all"), "\(fixture.name): cookie banner leaked")
        #expect(!markdown.contains("Sign in"), "\(fixture.name): sign-in link leaked")
        #expect(!markdown.contains("Skip to main content"), "\(fixture.name): skip link leaked")
        #expect(!markdown.contains("Sponsored deal"), "\(fixture.name): promo slot leaked")
        #expect(!markdown.contains("analytics beacon"), "\(fixture.name): hidden element leaked")
        #expect(!markdown.contains("Rating popup"), "\(fixture.name): modal leaked")
        #expect(
            !markdown.contains("another tab or window"),
            "\(fixture.name): header chrome leaked"
        )

        // Tag debris is impossible by construction: only text nodes and
        // renderer-generated markdown reach the output.
        #expect(!markdown.contains("<script"))

        print("FIXTURE \(fixture.name): \(html.count) html → \(markdown.count) md chars")
    }

    private func loadFixture(_ name: String) throws -> String {
        let bundle = Bundle(for: BundleToken.self)
        if let url = bundle.url(
            forResource: "\(name).html",
            withExtension: nil,
            subdirectory: "Fixtures"
        ) {
            return try String(contentsOf: url, encoding: .utf8)
        }
        // Fallback: source tree next to this file (dev runs without bundling).
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        return try String(
            contentsOf: source.appendingPathComponent("Fixtures/\(name).html"),
            encoding: .utf8
        )
    }
}
