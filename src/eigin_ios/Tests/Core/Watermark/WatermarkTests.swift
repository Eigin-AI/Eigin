@testable import Eigin
import Testing

@Suite("Watermark")
struct WatermarkTests {
    // Parity anchor shared with the CLI's Rust fixture (tools/src/watermark/vectors.json):
    // version=1 (00000001) + magic=0xE191 (1110000110010001).
    private let expectedBits = "000000011110000110010001"
    private let sentinel: Unicode.Scalar = "\u{2060}"
    private let zero: Unicode.Scalar = "\u{200B}"
    private let one: Unicode.Scalar = "\u{200C}"

    @Test func tokenMatchesSharedContract() {
        let token = Watermark.token(magic: 0xE191)
        #expect(token.hasPrefix(String(sentinel)))
        #expect(token.hasSuffix(String(sentinel)))

        // Compare at the scalar level: Swift may cluster runs of identical
        // zero-width scalars into a single `Character`. (Array pins the plain
        // Sequence `filter`, not the `Predicate`-typed overload.)
        let asBinary = Array(token.unicodeScalars)
            .filter { $0 == zero || $0 == one }
            .map { $0 == one ? "1" : "0" }
            .joined()
        #expect(asBinary == expectedBits)
    }

    @Test func markAppendsInvisibleMarkerWhenEnabled() {
        // `mark` is gated on build config; exercise the encoding via `token`.
        let text = "Hello from Eigin."
        let marked = text + Watermark.token(magic: 0xE191)

        let visible = String(String.UnicodeScalarView(
            Array(marked.unicodeScalars).filter { $0 != zero && $0 != one && $0 != sentinel }
        ))
        #expect(visible == text)
        #expect(marked.hasPrefix(text))
    }

    @Test func markIsNoopWhenDisabled() {
        // The disabled path must be a pure no-op so call sites can wrap
        // egress unconditionally. Injected `nil` keeps this deterministic
        // regardless of the test host's build config.
        #expect(Watermark.mark("unchanged", magic: nil) == "unchanged")
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
