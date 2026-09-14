use std::sync::atomic::AtomicUsize;
use std::sync::{Arc, Mutex};

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

    /// A stream that ends without a usage block — what a hedged request's loser
    /// produces (canceled before any token), or an upstream cut mid-generation.
    pub fn without_usage() -> Self {
        let body = "data: {\"choices\":[]}\n\ndata: [DONE]\n\n";
        Self {
            sse_body: body.as_bytes().to_vec(),
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

/// Upstream that records the forwarded request body so tests can assert what the
/// relay passed through, then returns a minimal SSE stream with a zero usage block.
#[derive(Clone)]
pub struct CapturingUpstream {
    captured: Arc<Mutex<Option<Bytes>>>,
    sse_body: Vec<u8>,
}

impl Default for CapturingUpstream {
    fn default() -> Self {
        let usage_chunk = r#"data: {"id":"x","usage":{"prompt_tokens":0,"completion_tokens":0}}"#;
        let body = format!("data: {{\"choices\":[]}}\n\n{usage_chunk}\n\ndata: [DONE]\n\n");
        Self {
            captured: Arc::new(Mutex::new(None)),
            sse_body: body.into_bytes(),
        }
    }
}

impl CapturingUpstream {
    /// The body the relay forwarded to the upstream on the most recent request.
    pub fn captured_body(&self) -> Option<Bytes> {
        self.captured.lock().unwrap().clone()
    }
}

#[async_trait::async_trait]
impl UpstreamClient for CapturingUpstream {
    async fn chat_completions(
        &self,
        body: Bytes,
        _api_key: &str,
    ) -> Result<UpstreamResponse, AppError> {
        *self.captured.lock().unwrap() = Some(body);
        use futures::stream;
        let chunk = Ok(Bytes::from(self.sse_body.clone()));
        Ok(UpstreamResponse::Stream(Box::new(stream::iter(vec![
            chunk,
        ]))))
    }
}

/// No-op upstream that always returns an empty stream. Used where inference
/// is not under test.
pub struct NoopUpstream;

/// Upstream that emits `chunks` SSE chunks spaced `interval` apart, counting
/// how many it generated — lazily, so the count tracks what the relay actually
/// pulled. `first_delay` postpones the first chunk, letting tests drop the
/// connection before any output crosses the relay.
pub struct SlowCountingUpstream {
    pub chunks: usize,
    pub interval: std::time::Duration,
    pub first_delay: Option<std::time::Duration>,
    pub produced: Arc<std::sync::atomic::AtomicUsize>,
}

impl SlowCountingUpstream {
    pub fn start(
        chunks: usize,
        interval: std::time::Duration,
    ) -> (Self, Arc<std::sync::atomic::AtomicUsize>) {
        Self::start_delayed(chunks, interval, None)
    }

    pub fn start_delayed(
        chunks: usize,
        interval: std::time::Duration,
        first_delay: Option<std::time::Duration>,
    ) -> (Self, Arc<std::sync::atomic::AtomicUsize>) {
        let produced = Arc::new(std::sync::atomic::AtomicUsize::new(0));
        (
            Self {
                chunks,
                interval,
                first_delay,
                produced: Arc::clone(&produced),
            },
            produced,
        )
    }

    fn chunk() -> Result<Bytes, AppError> {
        Ok(Bytes::from(
            "data: {\"choices\":[{\"delta\":{\"content\":\"x\"}}]}\n\n",
        ))
    }
}

#[async_trait::async_trait]
impl UpstreamClient for SlowCountingUpstream {
    async fn chat_completions(
        &self,
        _body: Bytes,
        _api_key: &str,
    ) -> Result<UpstreamResponse, AppError> {
        use futures::StreamExt;
        use std::sync::atomic::Ordering;
        use tokio_stream::wrappers::IntervalStream;

        let interval = self.interval;
        let rest = self.chunks.saturating_sub(1);
        let produced_tail = Arc::clone(&self.produced);
        let produced_head = Arc::clone(&self.produced);

        // IntervalStream only yields when polled, so the count tracks what the
        // relay actually pulled — nothing gets generated into a closed channel.
        let tail = IntervalStream::new(tokio::time::interval(interval))
            .skip(1) // an interval's first tick fires immediately
            .take(rest)
            .map(move |_| {
                produced_tail.fetch_add(1, Ordering::SeqCst);
                Self::chunk()
            });

        let head: eigin_relay::inference::upstream::BoxStream = match self.first_delay {
            None => Box::new(tail),
            Some(delay) => {
                let first = futures::stream::once(async move {
                    tokio::time::sleep(delay).await;
                    produced_head.fetch_add(1, Ordering::SeqCst);
                    Self::chunk()
                });
                // Pin once: boxed async futures are not Unpin, and Chain needs it.
                Box::new(Box::pin(first).chain(tail))
            }
        };
        Ok(UpstreamResponse::Stream(Box::new(head)))
    }
}

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

/// Upstream that splits a single SSE output line across two yielded chunks with
/// a gap between them — trains the relay to scan whole lines, not chunks.
pub struct SplitLineUpstream {
    first: Bytes,
    second: Bytes,
    gap: std::time::Duration,
    trailing: usize,
    interval: std::time::Duration,
    produced: Arc<AtomicUsize>,
}

impl SplitLineUpstream {
    #[allow(clippy::type_complexity)]
    pub fn start(
        gap: std::time::Duration,
        trailing: usize,
        interval: std::time::Duration,
    ) -> (Self, Arc<AtomicUsize>) {
        let produced = Arc::new(AtomicUsize::new(0));
        (
            Self {
                first: Bytes::from_static(
                    b"data: {\"choices\":[{\"delta\":{\"content\":", // line deliberately split here
                ),
                second: Bytes::from_static(b"\"x\"}}]}\n\n"),
                gap,
                trailing,
                interval,
                produced: Arc::clone(&produced),
            },
            produced,
        )
    }
}

#[async_trait::async_trait]
impl UpstreamClient for SplitLineUpstream {
    async fn chat_completions(
        &self,
        _body: Bytes,
        _api_key: &str,
    ) -> Result<UpstreamResponse, AppError> {
        use futures::StreamExt;
        use std::sync::atomic::Ordering as AtomicOrdering;
        use tokio_stream::wrappers::IntervalStream;

        let produced_head = Arc::clone(&self.produced);
        let produced_mid = Arc::clone(&self.produced);
        let produced_tail = Arc::clone(&self.produced);
        let first_chunk = self.first.clone();
        let second_chunk = self.second.clone();
        let gap = self.gap;
        let interval = self.interval;
        let trailing_count = self.trailing;

        let first = futures::stream::once(async move {
            produced_head.fetch_add(1, AtomicOrdering::SeqCst);
            Ok::<_, AppError>(first_chunk)
        });
        let mid = futures::stream::once(async move {
            tokio::time::sleep(gap).await;
            produced_mid.fetch_add(1, AtomicOrdering::SeqCst);
            Ok::<_, AppError>(second_chunk)
        });
        let trailing = IntervalStream::new(tokio::time::interval(interval))
            .skip(1) // an interval's first tick fires immediately
            .take(trailing_count)
            .map(move |_| {
                produced_tail.fetch_add(1, AtomicOrdering::SeqCst);
                Ok::<_, AppError>(Bytes::from_static(
                    b"data: {\"choices\":[{\"delta\":{\"content\":\"y\"}}]}\n\n",
                ))
            });
        Ok(UpstreamResponse::Stream(Box::new(
            Box::pin(first).chain(Box::pin(mid)).chain(trailing),
        )))
    }
}
