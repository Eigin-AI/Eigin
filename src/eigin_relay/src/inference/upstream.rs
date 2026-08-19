//! Upstream inference provider client.

use async_trait::async_trait;
use bytes::Bytes;
use futures::Stream;

use crate::error::AppError;

/// A streaming response from the upstream provider.
pub type BoxStream = Box<dyn Stream<Item = Result<Bytes, AppError>> + Send + Unpin>;

/// Upstream inference client.
#[async_trait]
pub trait UpstreamClient: Send + Sync {
    /// Send a chat completions request body to the upstream,
    /// returning either a streaming body or a complete JSON buffer.
    ///
    /// `body` is the raw JSON bytes to POST (with `stream_options` injected).
    /// `is_stream` tells us which content-type to expect.
    async fn chat_completions(
        &self,
        body: Bytes,
        api_key: &str,
    ) -> Result<UpstreamResponse, AppError>;
}

pub enum UpstreamResponse {
    /// SSE stream (streaming request). The caller relays chunks and scans for usage.
    Stream(BoxStream),
    /// Complete buffered body (non-streaming request).
    Buffer(Bytes),
}

/// Client implementation using `reqwest`.
pub struct ReqwestUpstreamClient {
    client: reqwest::Client,
    base_url: String,
    provider_id: String,
}

impl ReqwestUpstreamClient {
    pub fn new(client: reqwest::Client, base_url: String, provider_id: String) -> Self {
        Self {
            client,
            base_url,
            provider_id,
        }
    }
}

#[async_trait]
impl UpstreamClient for ReqwestUpstreamClient {
    async fn chat_completions(
        &self,
        body: Bytes,
        api_key: &str,
    ) -> Result<UpstreamResponse, AppError> {
        let base_url = self.base_url.trim().trim_end_matches('/');
        let api_key = api_key.trim();

        if base_url.is_empty() {
            tracing::error!("UPSTREAM_API_URL is empty");
            return Err(AppError::ServiceUnavailable(
                "upstream URL is not configured".into(),
            ));
        }
        if !base_url.starts_with("http://") && !base_url.starts_with("https://") {
            tracing::error!(base_url, "UPSTREAM_API_URL is missing an http(s) scheme");
            return Err(AppError::ServiceUnavailable(
                "upstream URL is misconfigured".into(),
            ));
        }

        let url = format!("{base_url}/chat/completions");

        let response = self
            .client
            .post(&url)
            .header("Authorization", format!("Bearer {api_key}"))
            .header("Content-Type", "application/json")
            .body(body)
            .send()
            .await
            .map_err(|e| {
                // `{:?}` names the failure kind and source (e.g. Builder / InvalidHeaderValue)
                // without printing the key. The bare Display is just "builder error".
                tracing::error!(provider = %self.provider_id, error = ?e, %url, "upstream request failed");
                if e.is_builder() {
                    // A request we failed to construct (bad URL or header value) is our
                    // own misconfiguration, not an upstream outage.
                    AppError::ServiceUnavailable("upstream request could not be built".into())
                } else if e.is_connect() {
                    AppError::Upstream("could not connect to upstream".into())
                } else if e.is_timeout() {
                    AppError::Upstream("upstream timed out".into())
                } else {
                    AppError::Upstream(format!("request failed: {e}"))
                }
            })?;

        if !response.status().is_success() {
            let status = response.status();
            // Never read or log the upstream error body: it can echo the request
            // (moderation / validation errors), which would leak the user's prompt.
            // Retain provider + status as safe triage metadata instead.
            tracing::warn!(provider = %self.provider_id, %status, "upstream returned an error status");
            let provider = &self.provider_id;
            return Err(AppError::Upstream(format!(
                "provider {provider} returned {status}"
            )));
        }

        // Determine from Content-Type whether this is a stream.
        let is_stream = response
            .headers()
            .get("content-type")
            .and_then(|v| v.to_str().ok())
            .map(|ct| ct.contains("text/event-stream"))
            .unwrap_or(false);

        if is_stream {
            use futures::StreamExt;
            let stream = response
                .bytes_stream()
                .map(|r| r.map_err(|e| AppError::Upstream(format!("stream error: {e}"))));
            Ok(UpstreamResponse::Stream(Box::new(stream)))
        } else {
            let bytes = response
                .bytes()
                .await
                .map_err(|e| AppError::Upstream(format!("body read error: {e}")))?;
            Ok(UpstreamResponse::Buffer(bytes))
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn client(base_url: &str) -> ReqwestUpstreamClient {
        ReqwestUpstreamClient::new(
            reqwest::Client::new(),
            base_url.to_owned(),
            "test-provider".to_owned(),
        )
    }

    #[tokio::test]
    async fn empty_url_is_service_unavailable() {
        let result = client("   ").chat_completions(Bytes::new(), "key").await;
        assert!(matches!(result, Err(AppError::ServiceUnavailable(_))));
    }

    #[tokio::test]
    async fn url_without_scheme_is_service_unavailable() {
        let result = client("api.berget.ai/v1")
            .chat_completions(Bytes::new(), "key")
            .await;
        assert!(matches!(result, Err(AppError::ServiceUnavailable(_))));
    }
}
