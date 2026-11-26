use super::*;

#[test]
fn streams_winner_and_replays_ancillary_events_before_useful_output() {
    block_on(async {
        let events = vec![
            InferenceEvent::ProviderMetadata {
                values: HashMap::from([("key".into(), "value".into())]),
            },
            text(""),
            text("answer"),
            finish(),
        ];
        let host = effects("primary", events.clone());
        let mut request = InferenceRequest::open(options(), host.clone())
            .await
            .unwrap();
        for event in events {
            assert_eq!(request.next().await.unwrap(), Some(event));
        }
        assert_eq!(request.next().await.unwrap(), None);
        assert_eq!(request.attempts().winning_model(), "primary");
        assert_eq!(*host.opens.lock().unwrap(), ["primary"]);
    });
}

#[test]
fn local_open_failure_propagates_before_consumption() {
    block_on(async {
        let mut input = options();
        input.local = true;
        let host = Arc::new(Effects::default());
        assert!(matches!(
            InferenceRequest::open(input, host.clone()).await,
            Err(RequestError::Classified {
                error: InferenceError::Http { status: 404, .. },
                ..
            })
        ));
        assert_eq!(
            *host.log.lock().unwrap(),
            ["prepare:primary", "open:primary"]
        );
    });
}

#[test]
fn local_empty_reply_is_delivered_without_cloud_racing() {
    block_on(async {
        let host = effects("primary", vec![finish()]);
        let mut input = options();
        input.local = true;
        let mut request = InferenceRequest::open(input, host).await.unwrap();
        assert_eq!(request.next().await.unwrap(), Some(finish()));
        assert_eq!(request.next().await.unwrap(), None);
    });
}

#[test]
fn refreshes_once_and_preserves_original_failure_through_failed_replacement() {
    block_on(async {
        let host = effects("last", vec![text("answer"), finish()]);
        host.ranking
            .lock()
            .unwrap()
            .extend(["absent".into(), "last".into()]);
        let mut request = InferenceRequest::open(options(), host.clone())
            .await
            .unwrap();
        assert_eq!(request.next().await.unwrap(), Some(text("answer")));
        assert_eq!(request.attempts().winning_model(), "last");
        assert!(request.attempts().retry_won());
        assert_eq!(
            *host.log.lock().unwrap(),
            [
                "prepare:primary",
                "open:primary",
                "failure:primary",
                "refresh",
                "rank:primary",
                "prepare:absent",
                "open:absent",
                "failure:primary",
                "rank:primary",
                "prepare:last",
                "open:last",
            ]
        );
    });
}

#[test]
fn failed_preparation_spends_switch_without_dispatching() {
    block_on(async {
        let host = Arc::new(Effects::default());
        host.ranking
            .lock()
            .unwrap()
            .extend(["large".into(), "absent".into(), "unused".into()]);
        host.failed_prepare.lock().unwrap().push("large".into());
        let mut request = InferenceRequest::open(options(), host.clone())
            .await
            .unwrap();
        assert!(matches!(
            request.next().await,
            Err(RequestError::Classified {
                error: InferenceError::Http { status: 404, .. },
                ..
            })
        ));
        assert_eq!(*host.opens.lock().unwrap(), ["primary", "absent"]);
        assert_eq!(*host.ranking.lock().unwrap(), ["unused"]);
        assert!(!request.attempts().should_report(true, false));
    });
}

#[test]
fn empty_cloud_reply_and_malformed_tool_calls_keep_recovery_categories() {
    block_on(async {
        for (events, invalid) in [
            (vec![finish()], false),
            (
                vec![
                    InferenceEvent::ToolCall {
                        call: InferenceToolCall {
                            id: "call".into(),
                            name: "tool".into(),
                            arguments: "[]".into(),
                            ..Default::default()
                        },
                    },
                    InferenceEvent::Finished {
                        reason: InferenceFinishReason::ToolCalls,
                    },
                ],
                true,
            ),
        ] {
            let host = effects("primary", events);
            let mut request = InferenceRequest::open(options(), host).await.unwrap();
            let error = request.next().await.unwrap_err();
            assert!(if invalid {
                matches!(error, RequestError::InvalidToolCall)
            } else {
                matches!(error, RequestError::MissingReply)
            });
        }
    });
}

#[test]
fn buffer_overflow_retains_its_error_and_discards_ancillary_events() {
    block_on(async {
        let host = effects("primary", vec![text(""), text("not delivered")]);
        let mut input = options();
        input.max_buffered_bytes = 63;
        let mut request = InferenceRequest::open(input, host).await.unwrap();
        assert!(matches!(
            request.next().await,
            Err(RequestError::BufferOverflow)
        ));
    });
}

#[test]
fn cancellation_before_first_read_prevents_dispatch() {
    block_on(async {
        let host = effects("primary", vec![text("answer")]);
        let mut request = InferenceRequest::open(options(), host.clone())
            .await
            .unwrap();
        request.cancellation().cancel();
        assert!(matches!(
            request.next().await,
            Err(RequestError::Inference(InferenceError::Cancelled))
        ));
        assert!(host.opens.lock().unwrap().is_empty());
    });
}

#[test]
fn tool_argument_acceptance_matches_foundation_without_rewriting_payloads() {
    block_on(async {
        for arguments in ["\u{feff}{}", "{\"a\":1,}", "{\"a\":[1,]}"] {
            let event = InferenceEvent::ToolCall {
                call: InferenceToolCall {
                    id: "call".into(),
                    name: "tool".into(),
                    arguments: arguments.into(),
                    ..Default::default()
                },
            };
            let host = effects("primary", vec![event.clone()]);
            let mut request = InferenceRequest::open(options(), host).await.unwrap();
            assert_eq!(request.next().await.unwrap(), Some(event));
        }
    });
}
