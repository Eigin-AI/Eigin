use super::*;

fn hedged() -> RequestOptions {
    RequestOptions {
        hedge: Some(RequestHedge {
            model: "hedge".into(),
            delay_ms: 0,
        }),
        ..options()
    }
}

#[test]
fn observed_hedge_open_failure_is_recorded_before_replacement_ranking() {
    block_on(async {
        let host = effects("primary", vec![]);
        let primary = host.streams.lock().unwrap()["primary"].clone();
        let (fail, wait) = futures::channel::oneshot::channel();
        *primary.pending.lock().unwrap() = Some(wait);
        host.streams
            .lock()
            .unwrap()
            .insert("replacement".into(), Stream::new(vec![text("answer")]));
        host.ranking.lock().unwrap().push_back("replacement".into());
        let mut request = InferenceRequest::open(hedged(), host.clone())
            .await
            .unwrap();
        let mut next = Box::pin(request.next());
        assert!(futures::poll!(&mut next).is_pending());
        assert!(host.log.lock().unwrap().contains(&"failure:hedge".into()));
        assert!(!host.log.lock().unwrap().contains(&"rank:primary".into()));
        fail.send(Err(RequestError::FirstEventTimeout)).unwrap();
        assert_eq!(next.await.unwrap(), Some(text("answer")));
        let log = host.log.lock().unwrap();
        let failure = log.iter().position(|item| item == "failure:hedge").unwrap();
        let ranking = log.iter().position(|item| item == "rank:primary").unwrap();
        assert!(failure < ranking);
    });
}

#[test]
fn hedge_wins_while_primary_open_is_suspended() {
    block_on(async {
        let host = effects("hedge", vec![text("answer"), finish()]);
        let (_release, wait) = futures::channel::oneshot::channel();
        host.opening.lock().unwrap().insert("primary".into(), wait);
        let mut request = InferenceRequest::open(hedged(), host.clone())
            .await
            .unwrap();
        assert_eq!(request.next().await.unwrap(), Some(text("answer")));
        assert_eq!(request.next().await.unwrap(), Some(finish()));
        assert_eq!(request.next().await.unwrap(), None);
        assert_eq!(request.attempts().winning_model(), "hedge");
        assert!(host.cancelled.lock().unwrap().contains(&0));
        assert_eq!(*host.opens.lock().unwrap(), ["primary", "hedge"]);
    });
}

#[test]
fn failed_hedge_open_preserves_primary_replay_and_completion() {
    block_on(async {
        let host = effects("primary", vec![text("answer"), finish()]);
        let primary = host.streams.lock().unwrap()["primary"].clone();
        let (speak, wait) = futures::channel::oneshot::channel();
        *primary.pending.lock().unwrap() = Some(wait);
        let mut request = InferenceRequest::open(hedged(), host.clone())
            .await
            .unwrap();
        let mut next = Box::pin(request.next());
        assert!(futures::poll!(&mut next).is_pending());
        assert!(host.log.lock().unwrap().contains(&"failure:hedge".into()));
        assert!(!primary.cancelled.load(Ordering::SeqCst));
        let ancillary = InferenceEvent::ProviderMetadata {
            values: HashMap::from([("key".into(), "value".into())]),
        };
        speak.send(Ok(Some(ancillary.clone()))).unwrap();
        assert_eq!(next.await.unwrap(), Some(ancillary));
        assert_eq!(request.next().await.unwrap(), Some(text("answer")));
        assert_eq!(request.next().await.unwrap(), Some(finish()));
        assert_eq!(request.next().await.unwrap(), None);
        assert_eq!(request.attempts().winning_model(), "primary");
    });
}

#[test]
fn winner_error_after_useful_output_propagates_without_replacement() {
    block_on(async {
        for winner in ["primary", "hedge"] {
            let host = effects(winner, vec![text("answer")]);
            let (_release, wait) = futures::channel::oneshot::channel();
            let input = if winner == "hedge" {
                host.opening.lock().unwrap().insert("primary".into(), wait);
                hedged()
            } else {
                options()
            };
            let error = RequestError::Classified {
                error: InferenceError::Http {
                    status: 503,
                    body: Some("unavailable".into()),
                },
                failure: crate::inference::routing::RoutingFailure::ProviderOverloaded,
            };
            host.streams.lock().unwrap()[winner]
                .events
                .lock()
                .unwrap()
                .push_back(Err(error.clone()));
            host.ranking.lock().unwrap().push_back("replacement".into());
            let mut request = InferenceRequest::open(input, host.clone()).await.unwrap();
            assert_eq!(request.next().await.unwrap(), Some(text("answer")));
            assert!(
                matches!(request.next().await, Err(RequestError::Classified {
            error: InferenceError::Http { status: 503, body: Some(body) },
            failure: crate::inference::routing::RoutingFailure::ProviderOverloaded,
        }) if body == "unavailable")
            );
            assert_eq!(request.attempts().winning_model(), winner);
            let expected = if winner == "hedge" {
                vec!["primary", "hedge"]
            } else {
                vec!["primary"]
            };
            assert_eq!(*host.opens.lock().unwrap(), expected);
            assert_eq!(*host.ranking.lock().unwrap(), ["replacement"]);
        }
    });
}

#[test]
fn primary_winning_before_hedge_delay_never_opens_hedge() {
    block_on(async {
        let host = effects("primary", vec![text("answer"), finish()]);
        let mut input = hedged();
        input.hedge.as_mut().unwrap().delay_ms = 60_000;
        let mut request = InferenceRequest::open(input, host.clone()).await.unwrap();
        assert_eq!(request.next().await.unwrap(), Some(text("answer")));
        assert_eq!(request.next().await.unwrap(), Some(finish()));
        assert_eq!(request.next().await.unwrap(), None);
        assert_eq!(*host.opens.lock().unwrap(), ["primary"]);
    });
}
