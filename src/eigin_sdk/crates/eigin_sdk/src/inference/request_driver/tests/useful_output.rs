use super::*;
use crate::clock::ExecutionClock;

fn metadata() -> InferenceEvent {
    InferenceEvent::ProviderMetadata {
        values: HashMap::from([("side".into(), "winner".into())]),
    }
}

#[test]
fn ancillary_and_invalid_tools_cannot_beat_useful_hedge() {
    block_on(async {
        for first in [
            metadata(),
            InferenceEvent::ToolCall {
                call: InferenceToolCall {
                    id: "invalid".into(),
                    kind: "function".into(),
                    name: "search".into(),
                    arguments: "{broken".into(),
                },
            },
        ] {
            let host = effects("hedge", vec![metadata(), text("answer"), finish()]);
            let primary = Stream::new(vec![]);
            primary.stall_at_end.store(true, Ordering::SeqCst);
            let (send, wait) = futures::channel::oneshot::channel();
            *primary.pending.lock().unwrap() = Some(wait);
            send.send(Ok(Some(first))).unwrap();
            host.streams
                .lock()
                .unwrap()
                .insert("primary".into(), primary);
            let mut input = options();
            input.hedge = Some(RequestHedge {
                model: "hedge".into(),
                delay_ms: 0,
            });
            let mut request = InferenceRequest::open(input, host).await.unwrap();
            for event in [metadata(), text("answer"), finish()] {
                assert_eq!(request.next().await.unwrap(), Some(event));
            }
            assert_eq!(request.next().await.unwrap(), None);
            assert_eq!(request.attempts().winning_model(), "hedge");
        }
    });
}

#[test]
fn valid_tool_wins_and_replays_metadata() {
    block_on(async {
        let tool = InferenceEvent::ToolCall {
            call: InferenceToolCall {
                id: "call".into(),
                kind: "function".into(),
                name: "search".into(),
                arguments: "{}".into(),
            },
        };
        let events = vec![
            metadata(),
            tool,
            InferenceEvent::Finished {
                reason: InferenceFinishReason::ToolCalls,
            },
        ];
        let host = effects("primary", events.clone());
        let mut request = InferenceRequest::open(options(), host).await.unwrap();
        for event in events {
            assert_eq!(request.next().await.unwrap(), Some(event));
        }
        assert_eq!(request.next().await.unwrap(), None);
        assert_eq!(request.attempts().winning_model(), "primary");
    });
}

#[test]
fn nonuseful_completion_and_overflow_retry_without_replaying_loser() {
    block_on(async {
        for overflow in [false, true] {
            let host = effects("primary", vec![metadata(), finish()]);
            host.streams.lock().unwrap().insert(
                "replacement".into(),
                Stream::new(vec![text("answer"), finish()]),
            );
            host.ranking.lock().unwrap().push_back("replacement".into());
            let mut input = options();
            if overflow {
                input.max_buffered_bytes = 1;
            }
            let mut request = InferenceRequest::open(input, host).await.unwrap();
            assert_eq!(request.next().await.unwrap(), Some(text("answer")));
            assert_eq!(request.next().await.unwrap(), Some(finish()));
            assert_eq!(request.next().await.unwrap(), None);
            assert_eq!(request.attempts().winning_model(), "replacement");
        }
    });
}

#[test]
fn metadata_does_not_disable_first_useful_output_ceiling() {
    block_on(async {
        let host = effects("primary", vec![metadata()]);
        host.streams.lock().unwrap()["primary"]
            .stall_at_end
            .store(true, Ordering::SeqCst);
        let mut input = options();
        input.ceiling_ms = 100;
        let clock = Arc::new(crate::clock::testing::ManualClock::default());
        let mut request =
            InferenceRequest::open_with_clock(input, host, clock.now(), clock.clone())
                .await
                .unwrap();
        let mut next = Box::pin(request.next());
        assert!(futures::poll!(&mut next).is_pending());
        clock.advance(std::time::Duration::from_millis(100));
        assert!(matches!(next.await, Err(RequestError::FirstEventTimeout)));
    });
}

#[test]
fn timed_out_open_cannot_reenter_after_replacement_wins() {
    block_on(async {
        let host = effects("replacement", vec![text("answer")]);
        let (late, wait) = futures::channel::oneshot::channel();
        host.opening.lock().unwrap().insert("primary".into(), wait);
        host.ranking.lock().unwrap().push_back("replacement".into());
        let mut input = options();
        input.ceiling_ms = 100;
        let clock = Arc::new(crate::clock::testing::ManualClock::default());
        let mut request =
            InferenceRequest::open_with_clock(input, host.clone(), clock.now(), clock.clone())
                .await
                .unwrap();
        let mut next = Box::pin(request.next());
        assert!(futures::poll!(&mut next).is_pending());
        clock.advance(std::time::Duration::from_millis(100));
        assert_eq!(next.await.unwrap(), Some(text("answer")));
        assert!(late.send(()).is_err());
        assert_eq!(request.next().await.unwrap(), None);
        assert_eq!(*host.opens.lock().unwrap(), ["primary", "replacement"]);
        assert_eq!(
            host.log
                .lock()
                .unwrap()
                .iter()
                .filter(|item| *item == "rank:primary")
                .count(),
            1
        );
    });
}

#[test]
fn second_silent_ceiling_cancels_replacement_without_another_chase() {
    block_on(async {
        let host = effects("primary", vec![]);
        let replacement = Stream::new(vec![]);
        replacement.stall_at_end.store(true, Ordering::SeqCst);
        let primary = host.streams.lock().unwrap()["primary"].clone();
        primary.stall_at_end.store(true, Ordering::SeqCst);
        host.streams
            .lock()
            .unwrap()
            .insert("replacement".into(), replacement.clone());
        host.ranking
            .lock()
            .unwrap()
            .extend(["replacement".into(), "unused".into()]);
        let mut input = options();
        input.ceiling_ms = 100;
        let clock = Arc::new(crate::clock::testing::ManualClock::default());
        let mut request =
            InferenceRequest::open_with_clock(input, host.clone(), clock.now(), clock.clone())
                .await
                .unwrap();
        let mut next = Box::pin(request.next());
        assert!(futures::poll!(&mut next).is_pending());
        clock.advance(std::time::Duration::from_millis(100));
        assert!(futures::poll!(&mut next).is_pending());
        clock.advance(std::time::Duration::from_millis(100));
        assert!(matches!(next.await, Err(RequestError::FirstEventTimeout)));
        assert!(primary.cancelled.load(Ordering::SeqCst));
        assert!(replacement.cancelled.load(Ordering::SeqCst));
        assert_eq!(*host.opens.lock().unwrap(), ["primary", "replacement"]);
        assert_eq!(*host.ranking.lock().unwrap(), ["unused"]);
    });
}
