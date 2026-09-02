//! Zero-width watermark encode/detect.
//!
//! A marker is a short run of invisible zero-width characters appended to the
//! end of a message. It is machine-readable and detectable, but honest about
//! its limits: a technical user can strip it and paraphrasing destroys it.
//!
//! The encoding is a published contract (`docs/src/watermarking.md`) that the
//! on-device Swift encoder must match exactly.

/// Bit `0` — zero-width space.
const ZERO: char = '\u{200B}';
/// Bit `1` — zero-width non-joiner.
const ONE: char = '\u{200C}';
/// Frames a marker on both sides — word joiner.
const SENTINEL: char = '\u{2060}';

/// Number of payload bits in a marker: 8 (version) + 16 (magic).
const PAYLOAD_BITS: usize = 24;

/// The canonical Eigin watermark. Detection validates against this.
pub const EIGIN_SIGNATURE: Signature = Signature {
    version: 1,
    magic: 0xE191,
};

/// A watermark payload: a scheme version and a fixed magic constant.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Signature {
    pub version: u8,
    pub magic: u16,
}

impl Signature {
    /// Payload as 24 bits, most-significant first: version then magic.
    #[cfg(test)]
    fn bits(self) -> [bool; PAYLOAD_BITS] {
        let mut bits = [false; PAYLOAD_BITS];
        let payload = ((self.version as u32) << 16) | (self.magic as u32);
        for (i, bit) in bits.iter_mut().enumerate() {
            let shift = PAYLOAD_BITS - 1 - i;
            *bit = (payload >> shift) & 1 == 1;
        }
        bits
    }

    fn from_bits(bits: &[bool]) -> Self {
        let mut payload: u32 = 0;
        for &bit in bits {
            payload = (payload << 1) | bit as u32;
        }
        Signature {
            version: ((payload >> 16) & 0xFF) as u8,
            magic: (payload & 0xFFFF) as u16,
        }
    }

    /// The invisible marker token for this signature.
    #[cfg(test)]
    fn token(self) -> String {
        let mut out = String::with_capacity(PAYLOAD_BITS + 2);
        out.push(SENTINEL);
        for bit in self.bits() {
            out.push(if bit { ONE } else { ZERO });
        }
        out.push(SENTINEL);
        out
    }
}

/// Result of scanning text for the Eigin watermark.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Detection {
    pub watermarked: bool,
    pub version: u8,
    pub count: usize,
}

/// Append a watermark to `text`.
///
/// `signature` is supplied at build time; `None` (an empty/disabled config)
/// returns the text unchanged. Kept for parity tests and the future SDK.
#[cfg(test)]
pub fn encode(text: &str, signature: Option<Signature>) -> String {
    match signature {
        Some(sig) => format!("{text}{}", sig.token()),
        None => text.to_string(),
    }
}

/// Scan `text` for valid Eigin markers.
///
/// Reports whether any marker with the canonical magic is present, the version
/// of the last valid marker, and how many were found.
pub fn detect(text: &str) -> Detection {
    let chars: Vec<char> = text.chars().collect();
    let sentinels: Vec<usize> = chars
        .iter()
        .enumerate()
        .filter(|&(_, &c)| c == SENTINEL)
        .map(|(i, _)| i)
        .collect();

    let mut count = 0;
    let mut version = 0;

    for pair in sentinels.windows(2) {
        let (start, end) = (pair[0], pair[1]);
        if end - start - 1 != PAYLOAD_BITS {
            continue;
        }
        let slice = &chars[start + 1..end];
        let mut bits = [false; PAYLOAD_BITS];
        let mut valid = true;
        for (i, &c) in slice.iter().enumerate() {
            match c {
                ZERO => bits[i] = false,
                ONE => bits[i] = true,
                _ => {
                    valid = false;
                    break;
                }
            }
        }
        if !valid {
            continue;
        }
        let sig = Signature::from_bits(&bits);
        // Match on magic only: an old detector should still recognise marks from
        // a newer scheme version. Detectability matters more than version gating.
        if sig.magic == EIGIN_SIGNATURE.magic {
            count += 1;
            version = sig.version;
        }
    }

    Detection {
        watermarked: count > 0,
        version,
        count,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn encode_then_detect_roundtrips() {
        let marked = encode("Hello from Eigin.", Some(EIGIN_SIGNATURE));
        let d = detect(&marked);
        assert!(d.watermarked);
        assert_eq!(d.version, EIGIN_SIGNATURE.version);
        assert_eq!(d.count, 1);
    }

    #[test]
    fn marker_is_invisible_and_appended() {
        let text = "Some assistant output.";
        let marked = encode(text, Some(EIGIN_SIGNATURE));
        // The visible content is unchanged (only zero-width chars added).
        let visible: String = marked
            .chars()
            .filter(|c| ![ZERO, ONE, SENTINEL].contains(c))
            .collect();
        assert_eq!(visible, text);
        assert!(marked.starts_with(text));
    }

    #[test]
    fn none_signature_is_noop() {
        let text = "No watermark here.";
        assert_eq!(encode(text, None), text);
        assert!(!detect(text).watermarked);
    }

    #[test]
    fn plain_text_is_not_watermarked() {
        assert!(!detect("Just some ordinary text with no marks.").watermarked);
    }

    #[test]
    fn foreign_magic_is_ignored() {
        let other = Signature {
            version: 1,
            magic: 0x1234,
        };
        let marked = encode("text", Some(other));
        assert!(!detect(&marked).watermarked);
    }

    #[test]
    fn counts_multiple_markers() {
        let once = encode("a", Some(EIGIN_SIGNATURE));
        let twice = encode(&once, Some(EIGIN_SIGNATURE));
        assert_eq!(detect(&twice).count, 2);
    }

    #[test]
    fn bits_roundtrip() {
        let bits = EIGIN_SIGNATURE.bits();
        assert_eq!(Signature::from_bits(&bits), EIGIN_SIGNATURE);
    }

    #[test]
    fn token_matches_expected_codepoints() {
        // Parity anchor: the Swift encoder must produce this exact sequence.
        // version=1 (00000001), magic=0xE191 (1110000110010001).
        let expected_bits = "000000011110000110010001";
        let token = EIGIN_SIGNATURE.token();
        let inner: String = token.chars().filter(|&c| c == ZERO || c == ONE).collect();
        let as_binary: String = inner
            .chars()
            .map(|c| if c == ONE { '1' } else { '0' })
            .collect();
        assert_eq!(as_binary, expected_bits);
        assert!(token.starts_with(SENTINEL));
        assert!(token.ends_with(SENTINEL));
    }

    /// Parity against the shared fixture (`vectors.json`).
    ///
    /// The Swift encoder is tested against the same fixture, so both languages
    /// agree byte-for-byte on the encoding contract.
    #[test]
    fn matches_shared_fixtures() {
        let raw = include_str!("vectors.json");
        let doc: serde_json::Value = serde_json::from_str(raw).expect("valid fixture json");

        let magic_hex = doc["signature"]["magic"].as_str().unwrap();
        let signature = Signature {
            version: doc["signature"]["version"].as_u64().unwrap() as u8,
            magic: u16::from_str_radix(magic_hex.trim_start_matches("0x"), 16).unwrap(),
        };

        for vector in doc["vectors"].as_array().unwrap() {
            let input = vector["input"].as_str().unwrap();
            let marked = vector["marked"].as_str().unwrap();

            assert_eq!(
                encode(input, Some(signature)),
                marked,
                "encode mismatch for {input:?}"
            );
            assert!(detect(marked).watermarked, "detect failed for {input:?}");
        }
    }
}
