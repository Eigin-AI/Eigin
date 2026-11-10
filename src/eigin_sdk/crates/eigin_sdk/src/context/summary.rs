use unicode_segmentation::UnicodeSegmentation;

/// Parsed summary or a rejection reason for host-owned diagnostics.
#[derive(Debug, PartialEq, Eq, uniffi::Enum)]
pub enum SummaryParseResult {
    /// A usable tagged summary.
    Accepted { summary: String },
    /// No exact opening tag was found.
    MissingOpeningTag { trimmed_length: u64 },
    /// The trimmed body contains fewer than 50 grapheme clusters.
    TooShort { body_length: u64 },
}

// Foundation whitespacesAndNewlines includes U+200B in addition to Unicode White_Space.
fn foundation_whitespace(c: char) -> bool {
    matches!(c, '\u{9}'..='\u{d}' | '\u{20}' | '\u{85}' | '\u{a0}' | '\u{1680}' | '\u{2000}'..='\u{200b}' | '\u{2028}' | '\u{2029}' | '\u{202f}' | '\u{205f}' | '\u{3000}')
}

/// Extracts the first tagged summary, accepting a missing closing tag.
/// Trims Foundation-compatible whitespace and requires 50 grapheme clusters.
#[uniffi::export]
pub fn parse_summary(raw: String) -> SummaryParseResult {
    let trimmed = raw.trim_matches(foundation_whitespace);
    let Some((_, rest)) = trimmed.split_once("<conversation_summary>") else {
        return SummaryParseResult::MissingOpeningTag {
            trimmed_length: trimmed.graphemes(true).count() as u64,
        };
    };
    let body = rest
        .split_once("</conversation_summary>")
        .map_or(rest, |(body, _)| body)
        .trim_matches(foundation_whitespace);
    let length = body.graphemes(true).count() as u64;
    if length < 50 {
        SummaryParseResult::TooShort {
            body_length: length,
        }
    } else {
        SummaryParseResult::Accepted {
            summary: body.to_owned(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn summary_tags_whitespace_and_minimum_length() {
        let body = "e\u{301}".repeat(50);
        for whitespace in [" \n\r\t", "\u{200b}", "\u{85}", "\u{a0}\u{3000}"] {
            for close in ["</conversation_summary>ignored", ""] {
                assert_eq!(
                    parse_summary(format!(
                        "preamble<conversation_summary>{whitespace}{body}{whitespace}{close}"
                    )),
                    SummaryParseResult::Accepted {
                        summary: body.clone()
                    }
                );
            }
        }
        assert_eq!(
            parse_summary(format!(
                "<conversation_summary>{}</conversation_summary>",
                "👨‍👩‍👧‍👦".repeat(49)
            )),
            SummaryParseResult::TooShort { body_length: 49 }
        );
        assert!(matches!(
            parse_summary("untagged output".repeat(20)),
            SummaryParseResult::MissingOpeningTag { .. }
        ));
        assert!(matches!(
            parse_summary("<CONVERSATION_SUMMARY>text".into()),
            SummaryParseResult::MissingOpeningTag { .. }
        ));
        assert_eq!(
            parse_summary(format!(
                "<conversation_summary>short</conversation_summary><conversation_summary>{body}"
            )),
            SummaryParseResult::TooShort { body_length: 5 }
        );
    }
}
