use super::*;

#[test]
fn cancellation_before_open_sends_nothing() {
    let _diagnostics = crate::diagnostics::delivery::tests::RECEIVER_TEST_LOCK
        .lock()
        .unwrap();
    let (provider, _, transport) = setup(&[]);
    let stream = provider.stream(input()).unwrap();
    stream.cancel();
    assert!(matches!(
        block_on(stream.open()),
        Err(InferenceError::Cancelled)
    ));
    assert!(transport.requests.lock().unwrap().is_empty());
}

#[test]
fn pending_open_is_busy_and_cancellation_closes_it() {
    let _diagnostics = crate::diagnostics::delivery::tests::RECEIVER_TEST_LOCK
        .lock()
        .unwrap();
    let (_, wallets, mut transport) = setup(&[]);
    transport.hold = true;
    let stream = make_provider(wallets.clone(), transport.clone())
        .stream(input())
        .unwrap();
    let mut open = Box::pin(stream.open());
    assert!(open.as_mut().now_or_never().is_none());
    assert!(matches!(block_on(stream.next()), Err(InferenceError::Busy)));
    stream.cancel();
    assert!(matches!(block_on(open), Err(InferenceError::Cancelled)));
    assert_eq!(transport.requests.lock().unwrap().len(), 1);
    assert!(!transport.closed.lock().unwrap().is_empty());
    assert!(wallets.exhausted.lock().unwrap().is_empty());
}

#[test]
fn dropped_open_cancels_instead_of_replaying() {
    let _diagnostics = crate::diagnostics::delivery::tests::RECEIVER_TEST_LOCK
        .lock()
        .unwrap();
    let (_, wallets, mut transport) = setup(&[]);
    transport.hold = true;
    let stream = make_provider(wallets, transport.clone())
        .stream(input())
        .unwrap();
    let mut open = Box::pin(stream.open());
    assert!(open.as_mut().now_or_never().is_none());
    drop(open);
    assert!(matches!(
        block_on(stream.open()),
        Err(InferenceError::Cancelled)
    ));
    assert_eq!(transport.requests.lock().unwrap().len(), 1);
    assert!(!transport.closed.lock().unwrap().is_empty());
}

#[test]
fn cancellation_during_wallet_callbacks_prevents_the_next_request() {
    let _diagnostics = crate::diagnostics::delivery::tests::RECEIVER_TEST_LOCK
        .lock()
        .unwrap();
    for during_selection in [true, false] {
        let (_, mut wallets, transport) = setup(&[402]);
        let handle = Arc::new(Mutex::new(std::sync::Weak::<EiginRelayStream>::new()));
        let weak = handle.clone();
        let cancel: Arc<dyn Fn() + Send + Sync> =
            Arc::new(move || weak.lock().unwrap().upgrade().unwrap().cancel());
        if during_selection {
            wallets.selected = Some(cancel);
        } else {
            wallets.rejected = Some(cancel);
        }
        let stream = make_provider(wallets, transport.clone())
            .stream(input())
            .unwrap();
        *handle.lock().unwrap() = Arc::downgrade(&stream);
        assert!(matches!(
            block_on(stream.open()),
            Err(InferenceError::Cancelled)
        ));
        assert_eq!(
            transport.requests.lock().unwrap().len(),
            usize::from(!during_selection)
        );
    }
}

#[test]
fn pending_body_cancellation_does_not_replay() {
    let _diagnostics = crate::diagnostics::delivery::tests::RECEIVER_TEST_LOCK
        .lock()
        .unwrap();
    let (_, wallets, mut transport) = setup(&[200]);
    transport.hold_body = true;
    let stream = make_provider(wallets.clone(), transport.clone())
        .stream(input())
        .unwrap();
    block_on(stream.open()).unwrap();
    let mut next = Box::pin(stream.next());
    assert!(next.as_mut().now_or_never().is_none());
    stream.cancel();
    assert!(matches!(block_on(next), Err(InferenceError::Cancelled)));
    assert_eq!(transport.requests.lock().unwrap().len(), 1);
    assert!(wallets.exhausted.lock().unwrap().is_empty());
}

#[test]
fn transport_failure_preserves_metadata_and_does_not_replay() {
    let _diagnostics = crate::diagnostics::delivery::tests::RECEIVER_TEST_LOCK
        .lock()
        .unwrap();
    let (_, wallets, mut transport) = setup(&[]);
    transport.hold = true;
    let stream = make_provider(wallets.clone(), transport.clone())
        .stream(input())
        .unwrap();
    let mut open = Box::pin(stream.open());
    assert!(open.as_mut().now_or_never().is_none());
    transport
        .pending
        .lock()
        .unwrap()
        .take()
        .unwrap()
        .fail_with_code("offline".into(), "NSURLErrorDomain".into(), -1009);
    assert!(matches!(
        block_on(open),
        Err(InferenceError::Transport {
            code: Some(-1009),
            ..
        })
    ));
    assert_eq!(transport.requests.lock().unwrap().len(), 1);
    assert!(wallets.exhausted.lock().unwrap().is_empty());
}

#[test]
fn cancellation_closes_a_successful_open_before_or_after_resumption() {
    let _diagnostics = crate::diagnostics::delivery::tests::RECEIVER_TEST_LOCK
        .lock()
        .unwrap();
    for resume_first in [false, true] {
        let (_, wallets, mut transport) = setup(&[]);
        transport.hold = true;
        let stream = make_provider(wallets.clone(), transport.clone())
            .stream(input())
            .unwrap();
        let mut open = Box::pin(stream.open());
        assert!(open.as_mut().now_or_never().is_none());
        transport
            .pending
            .lock()
            .unwrap()
            .take()
            .unwrap()
            .succeed(HttpResponseHead {
                status: 200,
                headers: Default::default(),
            });
        if resume_first {
            block_on(open.as_mut()).unwrap();
        }
        stream.cancel();
        if !resume_first {
            assert!(matches!(block_on(open), Err(InferenceError::Cancelled)));
        }
        assert!(matches!(
            block_on(stream.next()),
            Err(InferenceError::Cancelled)
        ));
        assert_eq!(transport.requests.lock().unwrap().len(), 1);
        assert_eq!(transport.closed.lock().unwrap().len(), 1);
        assert!(wallets.exhausted.lock().unwrap().is_empty());
    }
}

#[test]
fn cancellation_closes_the_replacement_attempt_without_another_request() {
    let _diagnostics = crate::diagnostics::delivery::tests::RECEIVER_TEST_LOCK
        .lock()
        .unwrap();
    for complete_headers in [false, true] {
        let (_, wallets, mut transport) = setup(&[]);
        transport.hold = true;
        let stream = make_provider(wallets.clone(), transport.clone())
            .stream(input())
            .unwrap();
        let mut open = Box::pin(stream.open());
        assert!(open.as_mut().now_or_never().is_none());
        transport
            .pending
            .lock()
            .unwrap()
            .take()
            .unwrap()
            .succeed(HttpResponseHead {
                status: 402,
                headers: Default::default(),
            });
        assert!(open.as_mut().now_or_never().is_none());
        assert_eq!(transport.requests.lock().unwrap().len(), 2);
        assert_eq!(*wallets.exhausted.lock().unwrap(), ["first"]);
        if complete_headers {
            transport
                .pending
                .lock()
                .unwrap()
                .take()
                .unwrap()
                .succeed(HttpResponseHead {
                    status: 200,
                    headers: Default::default(),
                });
        }
        stream.cancel();
        assert!(matches!(block_on(open), Err(InferenceError::Cancelled)));
        assert!(matches!(
            block_on(stream.next()),
            Err(InferenceError::Cancelled)
        ));
        let closed = transport.closed.lock().unwrap();
        assert_eq!(closed.len(), 2);
        assert_ne!(closed[0], closed[1]);
        assert_eq!(transport.requests.lock().unwrap().len(), 2);
    }
}
