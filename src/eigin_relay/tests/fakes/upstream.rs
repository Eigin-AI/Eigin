use bytes::Bytes;
use eigin_relay::AppError;
use eigin_relay::inference::upstream::{UpstreamClient, UpstreamResponse};

/// Fake upstream that returns a canned SSE stream with a usage block.
pub struct FakeUpstream {
    /// Canned SSE response body to return for every request.
    sse_body: Vec<u8>,
}

impl FakeUpstream {
    pub fn with_usage(prompt: u64, completion: u64) -> Self {
        // A minimal SSE stream: one delta chunk + one final usage chunk + [DONE].
        let usage_chunk = format!(
            r#"data: {{"id":"x","usage":{{"prompt_tokens":{prompt},"completion_tokens":{completion}}}}}"#
        );
        let body = format!("data: {{\"choices\":[]}}\n\n{usage_chunk}\n\ndata: [DONE]\n\n");
        Self {
            sse_body: body.into_bytes(),
        }
    }
}

#[async_trait::async_trait]
impl UpstreamClient for FakeUpstream {
    async fn chat_completions(
        &self,
        _body: Bytes,
        _api_key: &str,
    ) -> Result<UpstreamResponse, AppError> {
        use futures::stream;
        let chunk = Ok(Bytes::from(self.sse_body.clone()));
        let s = stream::iter(vec![chunk]);
        Ok(UpstreamResponse::Stream(Box::new(s)))
    }
}

/// Fake upstream that returns a canned buffered JSON response with a usage block.
pub struct BufferUpstream {
    body: Vec<u8>,
}

impl BufferUpstream {
    pub fn with_usage(prompt: u64, completion: u64) -> Self {
        let body = serde_json::json!({
            "id": "x",
            "choices": [],
            "usage": {
                "prompt_tokens": prompt,
                "completion_tokens": completion
            }
        });
        Self {
            body: serde_json::to_vec(&body).unwrap(),
        }
    }
}

#[async_trait::async_trait]
impl UpstreamClient for BufferUpstream {
    async fn chat_completions(
        &self,
        _body: Bytes,
        _api_key: &str,
    ) -> Result<UpstreamResponse, AppError> {
        Ok(UpstreamResponse::Buffer(Bytes::from(self.body.clone())))
    }
}

/// No-op upstream that always returns an empty stream. Used where inference
/// is not under test.
pub struct NoopUpstream;

#[async_trait::async_trait]
impl UpstreamClient for NoopUpstream {
    async fn chat_completions(
        &self,
        _body: Bytes,
        _api_key: &str,
    ) -> Result<UpstreamResponse, AppError> {
        use futures::stream;
        Ok(UpstreamResponse::Stream(Box::new(stream::empty())))
    }
}
