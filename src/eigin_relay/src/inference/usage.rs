//! Extracts the usage block from upstream SSE or JSON responses.
//!
//! For streaming requests, the usage block typically arrives in the final
//! `data:` chunk. We scan each SSE line as it passes through without buffering
//! the full stream.
//!
//! For non-streaming requests, we parse the complete JSON response.
//!
//! We never look at prompt/completion content — only the usage numbers.

use serde::Deserialize;

/// Token usage extracted from an upstream response.
#[derive(Debug, Clone, Default)]
pub struct UsageBlock {
    /// The number of prompt (input) tokens.
    pub prompt_tokens: u64,
    /// The number completion (output) tokens.
    pub completion_tokens: u64,
    /// The number of prompt tokens served from cache.
    pub cached_tokens: u64,
}

/// Internal deserialization types — not exported.
#[derive(Deserialize)]
struct RawUsage {
    prompt_tokens: Option<u64>,
    completion_tokens: Option<u64>,
    prompt_tokens_details: Option<RawPromptDetails>,
}

#[derive(Deserialize)]
struct RawPromptDetails {
    cached_tokens: Option<u64>,
}

#[derive(Deserialize)]
struct RawResponse {
    usage: Option<RawUsage>,
}

/// Try to extract a `UsageBlock` from a single SSE `data:` line's JSON payload.
///
/// Returns `None` if the line has no usage information or is not parseable.
/// This is called for every SSE line — most return `None`.
pub fn extract_from_sse_line(line: &str) -> Option<UsageBlock> {
    let json = line.strip_prefix("data: ")?;
    if json.trim() == "[DONE]" {
        return None;
    }
    parse_usage_json(json)
}

/// Extract a `UsageBlock` from a complete (non-streaming) JSON response body.
pub fn extract_from_response_body(body: &[u8]) -> Option<UsageBlock> {
    let text = std::str::from_utf8(body).ok()?;
    parse_usage_json(text)
}

fn parse_usage_json(json: &str) -> Option<UsageBlock> {
    let raw: RawResponse = serde_json::from_str(json).ok()?;
    let usage = raw.usage?;
    Some(UsageBlock {
        prompt_tokens: usage.prompt_tokens.unwrap_or(0),
        completion_tokens: usage.completion_tokens.unwrap_or(0),
        cached_tokens: usage
            .prompt_tokens_details
            .and_then(|d| d.cached_tokens)
            .unwrap_or(0),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn extracts_usage_from_streaming_chunk() {
        let line = r#"data: {"id":"x","usage":{"prompt_tokens":100,"completion_tokens":50}}"#;
        let u = extract_from_sse_line(line).unwrap();
        assert_eq!(u.prompt_tokens, 100);
        assert_eq!(u.completion_tokens, 50);
        assert_eq!(u.cached_tokens, 0);
    }

    #[test]
    fn extracts_cached_tokens() {
        let line = r#"data: {"usage":{"prompt_tokens":200,"completion_tokens":80,"prompt_tokens_details":{"cached_tokens":150}}}"#;
        let u = extract_from_sse_line(line).unwrap();
        assert_eq!(u.cached_tokens, 150);
    }

    #[test]
    fn done_sentinel_returns_none() {
        assert!(extract_from_sse_line("data: [DONE]").is_none());
    }

    #[test]
    fn non_usage_sse_chunk_returns_none() {
        let line = r#"data: {"id":"x","choices":[{"delta":{"content":"hi"}}]}"#;
        assert!(extract_from_sse_line(line).is_none());
    }

    #[test]
    fn extracts_from_non_streaming_body() {
        let body = br#"{"id":"x","usage":{"prompt_tokens":300,"completion_tokens":100}}"#;
        let u = extract_from_response_body(body).unwrap();
        assert_eq!(u.prompt_tokens, 300);
        assert_eq!(u.completion_tokens, 100);
    }

    #[test]
    fn body_without_usage_returns_none() {
        let body = br#"{"id":"x","choices":[]}"#;
        assert!(extract_from_response_body(body).is_none());
    }

    #[test]
    fn explicit_null_usage_returns_none() {
        // Upstream sends `"usage": null` in intermediate SSE chunks.
        let line = r#"data: {"id":"x","usage":null}"#;
        assert!(extract_from_sse_line(line).is_none());
    }

    #[test]
    fn non_data_sse_lines_return_none() {
        assert!(extract_from_sse_line("").is_none());
        assert!(extract_from_sse_line("event: ping").is_none());
        assert!(extract_from_sse_line(": keep-alive").is_none());
    }
}
