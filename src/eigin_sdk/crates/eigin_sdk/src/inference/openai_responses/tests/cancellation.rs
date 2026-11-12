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
fn stream(transport: &Transport) -> Arc<OpenAiResponsesStream> {
    OpenAiResponsesProvider::with_transport(
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
fn failed_error_body_keeps_http_prefix_and_open_failure() {
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
        .succeed(Some(b"subscription_sharing_user_not_eligible".to_vec()));
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
        Err(InferenceError::SubscriptionPlanNotEligible)
    ));
    assert!(matches!(
        block_on(operation.next()),
        Err(InferenceError::SubscriptionPlanNotEligible)
    ));
}
