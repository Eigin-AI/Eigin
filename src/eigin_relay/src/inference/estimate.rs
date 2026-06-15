//! Rough usage estimation for requests where upstream returns no usage block.
//!
//! We don't look at prompt content, just the total byte length of message strings.
//! The estimate is a rough reasonable average for English prose but can be slightly
//! off for code or non-Latin scripts.
//!
//! Without an upstream usage block, we can't know if prompt caching was applied,
//! so we assume cached tokens to be 0.

use serde_json::Value;

use crate::inference::usage::UsageBlock;

/// Estimated output tokens to assume when the real count is unknown.
const ESTIMATED_OUTPUT_TOKENS: u64 = 100;

/// Bytes per token, rough average across common tokenizers.
const BYTES_PER_TOKEN: u64 = 4;

/// Estimate a `UsageBlock` from the raw request body.
///
/// Sums the byte lengths of all `messages[].content` strings to estimate
/// prompt tokens. Output tokens are fixed at [`ESTIMATED_OUTPUT_TOKENS`].
/// Returns `None` if the body has no parseable `messages` array.
pub fn estimate_usage(body: &Value) -> Option<UsageBlock> {
    let messages = body.get("messages")?.as_array()?;

    let content_bytes: u64 = messages
        .iter()
        .filter_map(|m| m.get("content")?.as_str())
        .map(|s| s.len() as u64)
        .sum();

    // Guard against a zero-length estimate producing a free request.
    if content_bytes == 0 {
        return None;
    }

    Some(UsageBlock {
        prompt_tokens: (content_bytes / BYTES_PER_TOKEN).max(1),
        completion_tokens: ESTIMATED_OUTPUT_TOKENS,
        cached_tokens: 0,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn estimates_prompt_tokens_from_message_lengths() {
        let body = json!({
            "messages": [
                {"role": "user", "content": "a".repeat(400)}
            ]
        });

        let u = estimate_usage(&body).unwrap();
        // 400 bytes / 4 = 100 prompt tokens
        assert_eq!(u.prompt_tokens, 100);
        assert_eq!(u.completion_tokens, ESTIMATED_OUTPUT_TOKENS);
        assert_eq!(u.cached_tokens, 0);
    }

    #[test]
    fn sums_across_multiple_messages() {
        let body = json!({
            "messages": [
                {"role": "system", "content": "a".repeat(200)},
                {"role": "user",   "content": "a".repeat(200)}
            ]
        });

        let u = estimate_usage(&body).unwrap();
        // 400 bytes / 4 = 100 prompt tokens
        assert_eq!(u.prompt_tokens, 100);
    }

    #[test]
    fn skips_non_string_content() {
        // Vision messages use array content that this implementation doesn't estimate.
        let body = json!({
            "messages": [
                {"role": "user", "content": [{"type": "image_url", "url": "..."}]}
            ]
        });

        // No string content → None
        assert!(estimate_usage(&body).is_none());
    }

    #[test]
    fn returns_none_without_messages() {
        let body = json!({"model": "gpt-4o"});
        assert!(estimate_usage(&body).is_none());
    }

    #[test]
    fn minimum_one_prompt_token() {
        // A single byte of content should not produce 0 tokens.
        let body = json!({
            "messages": [{"role": "user", "content": "x"}]
        });
        let u = estimate_usage(&body).unwrap();
        assert_eq!(u.prompt_tokens, 1);
    }
}
