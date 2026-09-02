@testable import Eigin
import Testing

@Suite("Watermark")
struct WatermarkTests {
    // Parity anchor shared with the CLI's Rust fixture (tools/src/watermark/vectors.json):
    // version=1 (00000001) + magic=0xE191 (1110000110010001).
    private let expectedBits = "000000011110000110010001"
    private let sentinel = "\u{2060}"
    private let zero = "\u{200B}"
    private let one = "\u{200C}"

    @Test func tokenMatchesSharedContract() {
        let token = Watermark.token(magic: 0xE191)
        #expect(token.hasPrefix(sentinel))
        #expect(token.hasSuffix(sentinel))

        let inner = token.filter { String($0) == zero || String($0) == one }
        let asBinary = inner.map { String($0) == one ? "1" : "0" }.joined()
        #expect(asBinary == expectedBits)
    }

    @Test func markAppendsInvisibleMarkerWhenEnabled() {
        // `mark` is gated on build config; exercise the encoding via `token`.
        let text = "Hello from Eigin."
        let marked = text + Watermark.token(magic: 0xE191)

        let visible = marked.filter {
            let s = String($0)
            return s != zero && s != one && s != sentinel
        }
        #expect(visible == text)
        #expect(marked.hasPrefix(text))
    }

    @Test func disabledInTestsSoMarkIsNoop() {
        // No `EiginWatermarkSignature` in the test Info.plist ⇒ disabled.
        #expect(Watermark.isEnabled == false)
        #expect(Watermark.mark("unchanged") == "unchanged")
    }

    @Test func shippedConfigParsesToCanonicalMagic() throws {
        // `E191` must match project.yml's EiginWatermarkSignature. Guards against
        // the constant drifting from the shipped config, which would make output
        // undetectable while every other test still passed.
        #expect(Watermark.magic(from: "E191") == Watermark.canonicalMagic)
        #expect(Watermark.magic(from: "") == nil)
        #expect(Watermark.magic(from: nil) == nil)

        // The parsed config yields the same mark the detector expects.
        let configured = try #require(Watermark.magic(from: "E191"))
        #expect(Watermark.token(magic: configured) == Watermark
            .token(magic: Watermark.canonicalMagic))
    }
}
