//! Upstream inference provider client.

use std::time::Duration;

use async_trait::async_trait;
use bytes::Bytes;
use futures::Stream;

use crate::error::AppError;

/// Time allowed to establish the connection to an upstream provider.
const UPSTREAM_CONNECT_TIMEOUT: Duration = Duration::from_secs(15);

/// Max silence between streamed chunks before the upstream is treated as
/// stalled. Resets on each read, so long healthy generations are unaffected.
const UPSTREAM_READ_TIMEOUT: Duration = Duration::from_secs(30);

/// Builds the production HTTP client for upstream inference.
///
/// Uses connect + read timeouts and no total cap: a long streaming generation
/// survives as long as chunks keep arriving, while a hung handshake or a
/// silent connection is cut. A fired read timeout surfaces as
/// `AppError::Upstream` via the `is_timeout()` branch in `chat_completions`.
pub fn http_client() -> reqwest::Client {
    build_client(UPSTREAM_CONNECT_TIMEOUT, UPSTREAM_READ_TIMEOUT)
}

/// Builds an upstream client with explicit timeouts. Split out so tests can use
/// short durations without waiting on the production constants.
fn build_client(connect_timeout: Duration, read_timeout: Duration) -> reqwest::Client {
    reqwest::Client::builder()
        .connect_timeout(connect_timeout)
        .read_timeout(read_timeout)
        .build()
        .expect("upstream HTTP client build failed")
}

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

    // A server that accepts connections but never replies. Before timeouts were
    // configured this pinned the request forever; now the read timeout fires.
    #[tokio::test]
    async fn stalled_upstream_hits_read_timeout() {
        use std::time::Duration;
        use tokio::net::TcpListener;

        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();

        // Accept and hold sockets open, sending nothing back.
        tokio::spawn(async move {
            let mut held = Vec::new();
            loop {
                if let Ok((sock, _)) = listener.accept().await {
                    held.push(sock);
                }
            }
        });

        let stalling_client = ReqwestUpstreamClient::new(
            build_client(Duration::from_secs(5), Duration::from_millis(200)),
            format!("http://{addr}"),
            "test-provider".to_owned(),
        );

        // Outer guard: if the read timeout were ever dropped, the call would hang
        // forever. This makes that regression a fast, clear failure instead.
        let result = tokio::time::timeout(
            Duration::from_secs(5),
            stalling_client.chat_completions(Bytes::from_static(b"{}"), "key"),
        )
        .await
        .expect("request should hit the read timeout, not hang");

        match result {
            Err(AppError::Upstream(msg)) => assert!(msg.contains("timed out"), "got: {msg}"),
            Err(other) => panic!("expected upstream timeout, got: {other:?}"),
            Ok(_) => panic!("expected upstream timeout, got a response"),
        }
    }
}
