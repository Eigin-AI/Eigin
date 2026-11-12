use super::super::{
    streaming::{HttpFailurePolicy, InferenceStream, OpenFailureDelivery},
    types::*,
};
use super::stream::StreamParser;
use crate::http::*;
use std::sync::Arc;

/// Cancellable, pull-based provider stream. Only one open/next may be pending.
#[derive(uniffi::Object)]
pub struct OpenAiResponsesStream {
    inner: InferenceStream<StreamParser>,
}

impl OpenAiResponsesStream {
    pub(super) fn new(
        http: Arc<HttpOperation>,
        request: HttpRequest,
        input: InferenceCompletionInput,
    ) -> Arc<Self> {
        let parser = StreamParser::default();
        Arc::new(Self {
            inner: InferenceStream::new(
                http,
                request,
                input.model,
                parser,
                "inference.openai-responses",
                HttpFailurePolicy {
                    body_limit: 4000,
                    retain_partial_body: true,
                    normalize: super::error::normalize,
                },
                OpenFailureDelivery::Repeat,
            ),
        })
    }
}

#[uniffi::export]
impl OpenAiResponsesStream {
    /// Opens HTTP and validates status without consuming successful response data.
    pub async fn open(&self) -> Result<(), InferenceError> {
        self.inner.open().await
    }

    /// Produces the next ordered event, opening HTTP lazily if needed.
    pub async fn next(&self) -> Result<Option<InferenceEvent>, InferenceError> {
        self.inner.next().await
    }

    /// Stops network work and prevents further event delivery. Safe to repeat.
    pub fn cancel(&self) {
        self.inner.cancel();
    }
}
