import Foundation

/// Best-effort zero-width watermarking of Eigin-generated text.
///
/// A marker is a short run of invisible zero-width characters appended to text
/// when it leaves the app (full-message copy, email send/reply). It is
/// machine-readable and detectable, but honest about its limits: a technical
/// user can strip it and paraphrasing destroys it.
///
/// The encoding is a published contract (`docs/src/watermarking.md`) shared with
/// the CLI's Rust detector (`tools`). This module is deliberately self-contained
/// so it can be lifted behind the future Rust SDK unchanged.
enum Watermark {
    /// Bit `0` — zero-width space.
    private static let zero = "\u{200B}"
    /// Bit `1` — zero-width non-joiner.
    private static let one = "\u{200C}"
    /// Frames a marker on both sides — word joiner.
    private static let sentinel = "\u{2060}"

    /// Scheme version. Must match the Rust `EIGIN_SIGNATURE`.
    static let version: UInt8 = 1

    /// The magic the CLI detector validates against. Must match the Rust
    /// `EIGIN_SIGNATURE.magic` and the `EiginWatermarkSignature` build config.
    static let canonicalMagic: UInt16 = 0xE191

    /// Appends the Eigin watermark to `text`.
    ///
    /// A no-op when watermarking is disabled by build config, so call sites can
    /// wrap egress unconditionally.
    static func mark(_ text: String) -> String {
        guard let magic = configuredMagic else { return text }
        return text + token(magic: magic)
    }

    /// Whether watermarking is enabled for this build.
    static var isEnabled: Bool {
        configuredMagic != nil
    }

    /// The magic to stamp, read from build config.
    ///
    /// The `EiginWatermarkSignature` Info.plist value holds the magic as hex
    /// (e.g. `E191`). Empty, missing, or unparseable disables watermarking. It
    /// must match the detector's canonical magic to be detectable.
    static var configuredMagic: UInt16? {
        magic(from: Bundle.main.infoDictionary?["EiginWatermarkSignature"] as? String)
    }

    /// Parses a build-config magic value (hex). Empty, `nil`, or unparseable
    /// yields `nil` (watermarking disabled).
    static func magic(from value: String?) -> UInt16? {
        guard let value, !value.isEmpty else { return nil }
        return UInt16(value, radix: 16)
    }

    /// The invisible marker token: sentinel + 24 payload bits + sentinel.
    ///
    /// Payload is `version` (8 bits) then `magic` (16 bits), most-significant
    /// first.
    static func token(magic: UInt16) -> String {
        let payload = (UInt32(version) << 16) | UInt32(magic)
        var bits = sentinel
        for shift in stride(from: 23, through: 0, by: -1) {
            bits += (payload >> shift) & 1 == 1 ? one : zero
        }
        return bits + sentinel
    }
}
