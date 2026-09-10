//! Rough prompt-token estimate for requests where upstream returns no usage block.
//!
//! Text contributes byte length ÷ 4; image parts add a size-derived estimate so
//! vision requests get a realistic hold. Without an upstream usage block we assume
//! cached tokens are 0.

use serde_json::Value;

use crate::inference::usage::UsageBlock;

/// Estimated output tokens to assume when the real count is unknown.
const ESTIMATED_OUTPUT_TOKENS: u64 = 100;

/// Bytes per token, rough average across common tokenizers.
const BYTES_PER_TOKEN: u64 = 4;

/// Decoded image bytes per estimated prompt token. Calibrated so ~1 MB ≈ ~1000
/// tokens, the upper end of provider high-detail pricing (see #237).
const IMAGE_BYTES_PER_TOKEN: u64 = 1000;

/// Prompt tokens for a remote image URL whose size can't be inspected. OpenAI's
/// cost for a standard 1024×1024 `detail: high` image: `85 + 170 × 4`.
/// <https://openai-hd4n6.mintlify.app/docs/guides/images>
const ESTIMATED_REMOTE_IMAGE_TOKENS: u64 = 765;

/// Estimate a `UsageBlock` from the raw request body, or `None` if there's no
/// messages array or no estimable content.
pub fn estimate_usage(body: &Value) -> Option<UsageBlock> {
    let messages = body.get("messages")?.as_array()?;

    let mut text_bytes: u64 = 0;
    let mut image_tokens: u64 = 0;

    for message in messages {
        match message.get("content")? {
            Value::String(s) => text_bytes += s.len() as u64,
            Value::Array(parts) => {
                for part in parts {
                    match part.get("type").and_then(|t| t.as_str()) {
                        Some("text") => {
                            if let Some(t) = part.get("text").and_then(|v| v.as_str()) {
                                text_bytes += t.len() as u64;
                            }
                        }
                        Some("image_url") => {
                            if let Some(url) = part
                                .get("image_url")
                                .and_then(|v| v.get("url"))
                                .and_then(|v| v.as_str())
                            {
                                image_tokens += image_prompt_tokens(url);
                            }
                        }
                        _ => {}
                    }
                }
            }
            _ => {}
        }
    }

    // Floor of 1 token so a sub-`BYTES_PER_TOKEN` text string still counts.
    let text_tokens = if text_bytes == 0 {
        0
    } else {
        (text_bytes / BYTES_PER_TOKEN).max(1)
    };
    let prompt_tokens = text_tokens + image_tokens;

    if prompt_tokens == 0 {
        return None;
    }

    Some(UsageBlock {
        prompt_tokens,
        completion_tokens: ESTIMATED_OUTPUT_TOKENS,
        cached_tokens: 0,
    })
}

/// Prompt tokens for an `image_url.url`.
///
/// `data:` URLs derive decoded bytes from the base64 payload length (3 bytes →
/// 4 chars), ÷ [`IMAGE_BYTES_PER_TOKEN`]. Remote URLs get
/// [`ESTIMATED_REMOTE_IMAGE_TOKENS`].
fn image_prompt_tokens(url: &str) -> u64 {
    if let Some(payload) = url
        .strip_prefix("data:")
        .and_then(|s| s.split_once(',').map(|(_, b64)| b64))
    {
        let decoded_bytes = (payload.len() as u64) * 3 / 4;
        (decoded_bytes / IMAGE_BYTES_PER_TOKEN).max(1)
    } else {
        ESTIMATED_REMOTE_IMAGE_TOKENS
    }
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
    fn returns_none_without_messages() {
        let body = json!({"model": "gpt-4o"});
        assert!(estimate_usage(&body).is_none());
    }

    #[test]
    fn minimum_one_prompt_token() {
        let body = json!({
            "messages": [{"role": "user", "content": "x"}]
        });
        let u = estimate_usage(&body).unwrap();
        assert_eq!(u.prompt_tokens, 1);
    }

    #[test]
    fn estimates_array_text_parts() {
        let body = json!({
            "messages": [
                {"role": "user", "content": [{"type": "text", "text": "a".repeat(400)}]}
            ]
        });

        let u = estimate_usage(&body).unwrap();
        assert_eq!(u.prompt_tokens, 100);
    }

    #[test]
    fn estimates_data_url_image_from_payload_size() {
        // A 4000-char base64 payload → 3000 decoded bytes → 3 prompt tokens.
        let data_url = format!("data:image/jpeg;base64,{}", "a".repeat(4000));

        let body = json!({
            "messages": [
                {"role": "user", "content": [
                    {"type": "image_url", "image_url": {"url": data_url}}
                ]}
            ]
        });

        let u = estimate_usage(&body).unwrap();
        assert_eq!(u.prompt_tokens, 3);
    }

    #[test]
    fn estimates_remote_url_image_with_flat_default() {
        let body = json!({
            "messages": [
                {"role": "user", "content": [
                    {"type": "image_url", "image_url": {"url": "https://example.com/cat.png"}}
                ]}
            ]
        });

        let u = estimate_usage(&body).unwrap();
        assert_eq!(u.prompt_tokens, ESTIMATED_REMOTE_IMAGE_TOKENS);
    }

    #[test]
    fn all_image_request_is_estimated_not_none() {
        let data_url = format!("data:image/png;base64,{}", "a".repeat(4000));

        let body = json!({
            "messages": [
                {"role": "user", "content": [
                    {"type": "image_url", "image_url": {"url": data_url}}
                ]}
            ]
        });

        assert!(estimate_usage(&body).is_some());
    }

    #[test]
    fn sums_text_and_image_in_same_array_message() {
        let data_url = format!("data:image/jpeg;base64,{}", "a".repeat(4000));

        let body = json!({
            "messages": [
                {"role": "user", "content": [
                    {"type": "text", "text": "a".repeat(400)},
                    {"type": "image_url", "image_url": {"url": data_url}}
                ]}
            ]
        });

        let u = estimate_usage(&body).unwrap();
        // 400 text bytes / 4 = 100 text tokens, + 3 image tokens = 103.
        assert_eq!(u.prompt_tokens, 103);
    }

    #[test]
    fn ignores_unknown_content_part_types() {
        let body = json!({
            "messages": [
                {"role": "user", "content": [
                    {"type": "text", "text": "a".repeat(400)},
                    {"type": "audio_url", "audio_url": {"url": "..."}}
                ]}
            ]
        });

        let u = estimate_usage(&body).unwrap();
        // 400 / 4 = 100; the audio part is ignored.
        assert_eq!(u.prompt_tokens, 100);
    }

    #[test]
    fn returns_none_for_empty_messages() {
        let body = json!({"messages": []});
        assert!(estimate_usage(&body).is_none());
    }

    #[test]
    fn returns_none_when_content_parts_have_no_text_or_image() {
        let body = json!({
            "messages": [
                {"role": "user", "content": [{"type": "file", "file": {"id": "x"}}]}
            ]
        });
        assert!(estimate_usage(&body).is_none());
    }
}
