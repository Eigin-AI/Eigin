use crate::{http::*, inference::*};
use futures::{FutureExt, executor::block_on};
use std::sync::{Arc, Mutex};

#[derive(Clone, Default)]
struct Transport {
    head: Arc<Mutex<Option<Arc<HttpResponseHeadCallback>>>>,
    body: Arc<Mutex<Option<Arc<HttpBodyChunkCallback>>>>,
    closed: Arc<Mutex<Vec<u64>>>,
}

impl HttpTransport for Transport {
    fn start_request(&self, _: u64, _: HttpRequest, callback: Arc<HttpResponseHeadCallback>) {
        *self.head.lock().unwrap() = Some(callback);
    }

    fn read(&self, _: u64, callback: Arc<HttpBodyChunkCallback>) {
        *self.body.lock().unwrap() = Some(callback);
    }

    fn close(&self, id: u64) {
        self.closed.lock().unwrap().push(id);
    }
}

fn stream(transport: &Transport) -> Arc<AnthropicStream> {
    AnthropicProvider::with_transport(
        InferenceProviderConfig {
            base_url: "https://example.test".into(),
            api_token: "test".into(),
            extra_headers: Default::default(),
        },
        Box::new(transport.clone()),
    )
    .stream(InferenceCompletionInput::default())
    .unwrap()
}

fn headers(transport: &Transport, status: u16) {
    transport
        .head
        .lock()
        .unwrap()
        .take()
        .unwrap()
        .succeed(HttpResponseHead {
            status,
            headers: Default::default(),
        });
}

#[test]
fn cancel_before_headers_during_body_and_after_open() {
    let _lock = crate::diagnostics::delivery::tests::RECEIVER_TEST_LOCK
        .lock()
        .unwrap();

    let transport = Transport::default();
    let operation = stream(&transport);
    operation.cancel();

    assert!(matches!(
        block_on(operation.open()),
        Err(InferenceError::Cancelled)
    ));
    assert!(transport.head.lock().unwrap().is_none());

    for step in 0..4 {
        let transport = Transport::default();
        let operation = stream(&transport);
        let mut open = Box::pin(operation.open());

        assert!(open.as_mut().now_or_never().is_none());
        assert!(matches!(
            block_on(operation.next()),
            Err(InferenceError::Busy)
        ));

        if step > 0 {
            headers(&transport, 200);
        }
        if step > 1 {
            block_on(open.as_mut()).unwrap();
        }

        let mut next = Box::pin(operation.next());
        if step == 3 {
            assert!(next.as_mut().now_or_never().is_none());
        }

        operation.cancel();

        if step < 2 {
            assert!(matches!(block_on(open), Err(InferenceError::Cancelled)));
        }
        if step == 3 {
            assert!(matches!(block_on(next), Err(InferenceError::Cancelled)));
        }
        assert!(matches!(
            block_on(operation.next()),
            Err(InferenceError::Cancelled)
        ));
        assert_eq!(transport.closed.lock().unwrap().len(), 1);
    }
}

#[test]
fn dropped_pending_calls_cancel_and_independent_streams_continue() {
    let _lock = crate::diagnostics::delivery::tests::RECEIVER_TEST_LOCK
        .lock()
        .unwrap();

    for during_body in [false, true] {
        let transport = Transport::default();
        let operation = stream(&transport);
        let mut open = Box::pin(operation.open());

        assert!(open.as_mut().now_or_never().is_none());

        if during_body {
            headers(&transport, 200);
            block_on(open).unwrap();

            let mut next = Box::pin(operation.next());
            assert!(next.as_mut().now_or_never().is_none());
            drop(next);
        } else {
            drop(open);
        }
        assert!(matches!(
            block_on(operation.next()),
            Err(InferenceError::Cancelled)
        ));

        let independent = Transport::default();
        let other = stream(&independent);
        let mut open = Box::pin(other.open());
        assert!(open.as_mut().now_or_never().is_none());
        headers(&independent, 200);
        block_on(open).unwrap();
        assert!(independent.closed.lock().unwrap().is_empty());
    }
}

#[test]
fn failed_error_body_preserves_transport_failure() {
    let _lock = crate::diagnostics::delivery::tests::RECEIVER_TEST_LOCK
        .lock()
        .unwrap();

    let transport = Transport::default();
    let operation = stream(&transport);
    let mut open = Box::pin(operation.open());

    assert!(open.as_mut().now_or_never().is_none());

    headers(&transport, 403);
    assert!(open.as_mut().now_or_never().is_none());

    transport
        .body
        .lock()
        .unwrap()
        .take()
        .unwrap()
        .succeed(Some(b"partial error body".to_vec()));
    assert!(open.as_mut().now_or_never().is_none());

    transport
        .body
        .lock()
        .unwrap()
        .take()
        .unwrap()
        .fail("reset".into());

    assert!(matches!(
        block_on(open),
        Err(InferenceError::Transport { .. })
    ));
    assert!(matches!(
        block_on(operation.next()),
        Err(InferenceError::Transport { .. })
    ));
}

#[test]
fn discovery_and_validation_cancel_during_headers_and_body() {
    let _lock = crate::diagnostics::delivery::tests::RECEIVER_TEST_LOCK
        .lock()
        .unwrap();

    for validation in [false, true] {
        for during_body in [false, true] {
            let transport = Transport::default();
            let provider = AnthropicProvider::with_transport(
                InferenceProviderConfig {
                    base_url: "https://example.test".into(),
                    api_token: "test".into(),
                    extra_headers: Default::default(),
                },
                Box::new(transport.clone()),
            );
            let discovery = provider.discovery();
            let check = provider.key_validation();

            let mut pending = Box::pin(async {
                if validation {
                    check.validate_api_key("model".into()).await
                } else {
                    discovery.fetch_models().await.map(|_| ())
                }
            });
            assert!(pending.as_mut().now_or_never().is_none());

            if during_body {
                headers(&transport, 200);
                assert!(pending.as_mut().now_or_never().is_none());
                assert!(transport.body.lock().unwrap().is_some());
            }

            if validation {
                check.cancel();
            } else {
                discovery.cancel();
            }

            assert!(matches!(block_on(pending), Err(InferenceError::Cancelled)));
            assert_eq!(transport.closed.lock().unwrap().len(), 1);
        }
    }
}

#[test]
fn error_body_is_bounded_even_when_server_never_finishes() {
    let _lock = crate::diagnostics::delivery::tests::RECEIVER_TEST_LOCK
        .lock()
        .unwrap();

    let transport = Transport::default();
    let operation = stream(&transport);
    let mut open = Box::pin(operation.open());

    assert!(open.as_mut().now_or_never().is_none());

    headers(&transport, 500);
    assert!(open.as_mut().now_or_never().is_none());

    transport
        .body
        .lock()
        .unwrap()
        .take()
        .unwrap()
        .succeed(Some(vec![b'x'; 2500]));

    assert!(
        matches!(block_on(open), Err(InferenceError::Http {status:500, body:Some(body)}) if body.len() == 2000)
    );
    assert_eq!(transport.closed.lock().unwrap().len(), 1);
}

#[test]
fn completed_error_line_returns_before_a_stalled_remainder() {
    let _lock = crate::diagnostics::delivery::tests::RECEIVER_TEST_LOCK
        .lock()
        .unwrap();

    for separator in ["\n", "\r", "\r\n"] {
        let transport = Transport::default();
        let operation = stream(&transport);
        let mut open = Box::pin(operation.open());

        assert!(open.as_mut().now_or_never().is_none());

        headers(&transport, 500);
        assert!(open.as_mut().now_or_never().is_none());

        for part in [format!("first{separator}"), "x".repeat(600)] {
            transport
                .body
                .lock()
                .unwrap()
                .take()
                .unwrap()
                .succeed(Some(part.into_bytes()));
            assert!(open.as_mut().now_or_never().is_none());
        }

        // The separator is delivered separately from the text; a CR is sufficient.
        transport
            .body
            .lock()
            .unwrap()
            .take()
            .unwrap()
            .succeed(Some(vec![separator.as_bytes()[0]]));

        assert!(
            matches!(block_on(open), Err(InferenceError::Http {status:500,body:Some(body)}) if body == format!("first{}", "x".repeat(600)))
        );
        assert_eq!(transport.closed.lock().unwrap().len(), 1);
    }
}
