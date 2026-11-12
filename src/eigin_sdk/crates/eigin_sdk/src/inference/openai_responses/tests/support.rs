use crate::http::*;
use crate::inference::*;
use futures::executor::block_on;
use serde_json::Value;
use std::{
    collections::VecDeque,
    sync::{
        Arc, Mutex,
        atomic::{AtomicUsize, Ordering},
    },
};

#[derive(Clone)]
pub(super) struct ScriptedHttpTransport {
    pub(super) status: u16,
    pub(super) body: Vec<u8>,
    pub(super) chunk_size: Arc<AtomicUsize>,
    pub(super) chunks: Arc<Mutex<VecDeque<Vec<u8>>>>,
    pub(super) requests: Arc<Mutex<Vec<HttpRequest>>>,
}

impl HttpTransport for ScriptedHttpTransport {
    fn start_request(
        &self,
        _: u64,
        request: HttpRequest,
        completion: Arc<HttpResponseHeadCallback>,
    ) {
        self.requests.lock().unwrap().push(request);
        // One-byte reads exercise UTF-8 and framing across transport boundaries.
        *self.chunks.lock().unwrap() = self
            .body
            .chunks(self.chunk_size.load(Ordering::Relaxed))
            .map(<[u8]>::to_vec)
            .collect();
        completion.succeed(HttpResponseHead {
            status: self.status,
            headers: Default::default(),
        });
    }

    fn read(&self, _: u64, completion: Arc<HttpBodyChunkCallback>) {
        completion.succeed(self.chunks.lock().unwrap().pop_front());
    }

    fn close(&self, _: u64) {}
}

pub(super) fn provider(
    base: &str,
    status: u16,
    body: impl AsRef<[u8]>,
) -> (Arc<OpenAiResponsesProvider>, ScriptedHttpTransport) {
    let transport = ScriptedHttpTransport {
        status,
        body: body.as_ref().to_vec(),
        chunk_size: Arc::new(AtomicUsize::new(1)),
        chunks: Default::default(),
        requests: Default::default(),
    };
    let provider = OpenAiResponsesProvider::with_transport(
        InferenceProviderConfig {
            base_url: base.into(),
            api_token: "test-key".into(),
            extra_headers: [("X-Example".into(), "extra".into())].into(),
        },
        Box::new(transport.clone()),
    );
    (provider, transport)
}
pub(super) fn input() -> InferenceCompletionInput {
    InferenceCompletionInput {
        model: "test-model".into(),
        ..Default::default()
    }
}
pub(super) fn sse(values: &[Value]) -> String {
    values.iter().map(|v| format!("data: {v}\n\n")).collect()
}
pub(super) fn collect(
    provider: &OpenAiResponsesProvider,
    input: InferenceCompletionInput,
) -> (Vec<InferenceEvent>, Result<(), InferenceError>) {
    let _registration = crate::diagnostics::delivery::tests::RECEIVER_TEST_LOCK
        .lock()
        .unwrap();
    block_on(async {
        let stream = provider.stream(input).unwrap();
        let mut events = vec![];
        loop {
            match stream.next().await {
                Ok(Some(event)) => events.push(event),
                Ok(None) => return (events, Ok(())),
                Err(error) => return (events, Err(error)),
            }
        }
    })
}
pub(super) fn request_body(transport: &ScriptedHttpTransport) -> Value {
    serde_json::from_slice(&transport.requests.lock().unwrap().last().unwrap().body).unwrap()
}
