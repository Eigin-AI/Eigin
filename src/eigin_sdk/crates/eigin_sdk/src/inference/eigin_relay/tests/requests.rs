use super::*;

#[test]
fn initial_402_advances_wallet_and_preserves_request() {
    let _diagnostics = crate::diagnostics::delivery::tests::RECEIVER_TEST_LOCK
        .lock()
        .unwrap();
    let (provider, wallets, transport) = setup(&[402, 200]);
    block_on(async {
        let stream = provider.stream(input()).unwrap();
        stream.open().await.unwrap();
        stream.open().await.unwrap();
        assert!(
            matches!(stream.next().await.unwrap(), Some(InferenceEvent::ContentDelta { text }) if text == "hello")
        );
        while stream.next().await.unwrap().is_some() {}
    });
    assert_eq!(*wallets.exhausted.lock().unwrap(), ["first"]);
    let requests = transport.requests.lock().unwrap();
    assert_eq!(requests.len(), 2);
    assert_eq!(requests[0].url, "https://relay.test/v1/chat/completions");
    assert_eq!(requests[0].headers["authorization"], "Bearer first");
    assert_eq!(requests[1].headers["authorization"], "Bearer second");
    assert_eq!(requests[0].headers["x-eigin-key"], "relay-key");
    assert_eq!(requests[0].body, requests[1].body);
    let body: serde_json::Value = serde_json::from_slice(&requests[0].body).unwrap();
    assert_eq!(body["reasoning_effort"], "none");
}

#[test]
fn only_initial_402_retries() {
    let _diagnostics = crate::diagnostics::delivery::tests::RECEIVER_TEST_LOCK
        .lock()
        .unwrap();
    for status in [401, 403, 429, 500] {
        let (provider, wallets, transport) = setup(&[status]);
        let stream = provider.stream(input()).unwrap();
        for _ in 0..2 {
            assert!(
                matches!(block_on(stream.open()), Err(InferenceError::Http { status: actual, .. }) if actual == status)
            );
        }
        assert_eq!(transport.requests.lock().unwrap().len(), 1);
        assert!(wallets.exhausted.lock().unwrap().is_empty());
    }
}

#[test]
fn exhausted_or_empty_wallets_stop_without_repeating_requests() {
    let _diagnostics = crate::diagnostics::delivery::tests::RECEIVER_TEST_LOCK
        .lock()
        .unwrap();
    let (provider, wallets, transport) = setup(&[402, 402]);
    assert!(matches!(
        block_on(provider.stream(input()).unwrap().open()),
        Err(InferenceError::NoCredits)
    ));
    assert_eq!(transport.requests.lock().unwrap().len(), 2);
    assert_eq!(*wallets.exhausted.lock().unwrap(), ["first", "second"]);
    wallets.tokens.lock().unwrap().clear();
    assert!(matches!(
        block_on(provider.stream(input()).unwrap().open()),
        Err(InferenceError::NoCredits)
    ));
    assert_eq!(transport.requests.lock().unwrap().len(), 2);
}

#[test]
fn broken_wallet_source_cannot_repeat_a_token() {
    let _diagnostics = crate::diagnostics::delivery::tests::RECEIVER_TEST_LOCK
        .lock()
        .unwrap();
    let (_, mut wallets, transport) = setup(&[402]);
    wallets.repeated = true;
    let stream = make_provider(wallets, transport.clone())
        .stream(input())
        .unwrap();
    assert!(matches!(
        block_on(stream.open()),
        Err(InferenceError::WalletUnavailable)
    ));
    assert_eq!(transport.requests.lock().unwrap().len(), 1);
}

#[test]
fn callback_failure_does_not_send_request() {
    let _diagnostics = crate::diagnostics::delivery::tests::RECEIVER_TEST_LOCK
        .lock()
        .unwrap();
    let (_, mut wallets, transport) = setup(&[]);
    wallets.unavailable = true;
    let stream = make_provider(wallets, transport.clone())
        .stream(input())
        .unwrap();
    assert!(matches!(
        block_on(stream.open()),
        Err(InferenceError::WalletUnavailable)
    ));
    assert!(transport.requests.lock().unwrap().is_empty());
}

#[test]
fn discovery_sends_only_relay_key_and_sorts_models() {
    let _diagnostics = crate::diagnostics::delivery::tests::RECEIVER_TEST_LOCK
        .lock()
        .unwrap();
    let (_, mut wallets, transport) = setup(&[]);
    wallets.unavailable = true;
    transport
        .replies
        .lock()
        .unwrap()
        .push_back((200, br#"{"data":[{"id":"z"},{"id":"a"}]}"#.to_vec()));
    let provider = make_provider(wallets, transport.clone());
    assert_eq!(
        block_on(provider.discovery().fetch_models()).unwrap(),
        ["a", "z"]
    );
    let requests = transport.requests.lock().unwrap();
    assert_eq!(requests[0].url, "https://relay.test/v1/models");
    assert!(!requests[0].headers.contains_key("authorization"));
    assert_eq!(requests[0].headers["x-eigin-key"], "relay-key");
}

#[test]
fn inline_errors_never_advance_wallets() {
    let _diagnostics = crate::diagnostics::delivery::tests::RECEIVER_TEST_LOCK
        .lock()
        .unwrap();
    let (provider, wallets, transport) = setup(&[]);
    transport.replies.lock().unwrap().push_back((
        200,
        b"data: {\"error\":{\"message\":\"credits\",\"code\":402}}\n\n".to_vec(),
    ));
    let stream = provider.stream(input()).unwrap();
    assert!(block_on(stream.next()).is_err());
    assert_eq!(transport.requests.lock().unwrap().len(), 1);
    assert!(wallets.exhausted.lock().unwrap().is_empty());
}

#[test]
fn terminal_errors_are_delivered_once_by_next() {
    let _diagnostics = crate::diagnostics::delivery::tests::RECEIVER_TEST_LOCK
        .lock()
        .unwrap();
    for status in [402, 500] {
        let (provider, _, _) = setup(&[status, status]);
        let stream = provider.stream(input()).unwrap();
        assert!(block_on(stream.next()).is_err());
        assert!(block_on(stream.next()).unwrap().is_none());
        assert!(block_on(stream.open()).is_err());
    }
    let (provider, _, transport) = setup(&[]);
    transport.replies.lock().unwrap().push_back((
        200,
        b"data: {\"error\":{\"message\":\"failed\"}}\n\n".to_vec(),
    ));
    let stream = provider.stream(input()).unwrap();
    assert!(block_on(stream.next()).is_err());
    assert!(block_on(stream.next()).unwrap().is_none());
}

#[test]
fn missing_relay_key_rejects_provider_without_io() {
    let _diagnostics = crate::diagnostics::delivery::tests::RECEIVER_TEST_LOCK
        .lock()
        .unwrap();
    let transport = Transport::default();
    let provider = EiginRelayProvider::with_transport(
        EiginRelayProviderConfig {
            base_url: "https://relay.test".into(),
            relay_key: String::new(),
        },
        Box::new(Wallets::default()),
        Box::new(transport.clone()),
    );
    assert!(matches!(
        provider,
        Err(InferenceError::EiginRelayNotConfigured)
    ));
    assert!(transport.requests.lock().unwrap().is_empty());
}

#[test]
fn failed_exhaustion_update_stops_failover() {
    let _diagnostics = crate::diagnostics::delivery::tests::RECEIVER_TEST_LOCK
        .lock()
        .unwrap();
    let (_, mut wallets, transport) = setup(&[402]);
    wallets.reject_update = true;
    let stream = make_provider(wallets, transport.clone())
        .stream(input())
        .unwrap();
    assert!(matches!(
        block_on(stream.open()),
        Err(InferenceError::WalletUnavailable)
    ));
    assert_eq!(transport.requests.lock().unwrap().len(), 1);
}
