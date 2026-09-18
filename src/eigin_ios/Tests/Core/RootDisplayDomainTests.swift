@testable import Eigin
import Foundation
import Testing

@Suite("URL root display domain")
struct RootDisplayDomainTests {
    private func domain(_ host: String) -> String {
        URL(string: "https://\(host)/x")?.rootDisplayDomain() ?? ""
    }

    @Test func reducesSubdomainsToTheRoot() {
        #expect(domain("images.unsplash.com") == "unsplash.com")
        #expect(domain("cdn.assets.example.org") == "example.org")
        #expect(domain("a.b.c.example.co") == "example.co")
    }

    @Test func keepsShortHostsWhole() {
        #expect(domain("unsplash.com") == "unsplash.com")
        #expect(domain("example.com") == "example.com")
        #expect(domain("localhost") == "localhost")
    }

    @Test func dropsWWWStatically() {
        #expect(domain("www.unsplash.com") == "unsplash.com")
        #expect(domain("www.gov.uk") == "gov.uk")
    }

    @Test func keepsKnownTwoPartSuffixes() {
        #expect(domain("www.bbc.co.uk") == "bbc.co.uk")
        #expect(domain("news.com.au") == "news.com.au")
    }

    @Test func leavesIPLiteralsAlone() {
        #expect(domain("192.168.1.10") == "192.168.1.10")
        #expect(URL(string: "https://[2001:db8::1]/x")?.rootDisplayDomain() == "2001:db8::1")
    }

    @Test func emptyWithoutAHost() {
        let url = URL(string: "data:image/png;base64,AAAA")
        #expect(url?.rootDisplayDomain() == "")
    }
}
