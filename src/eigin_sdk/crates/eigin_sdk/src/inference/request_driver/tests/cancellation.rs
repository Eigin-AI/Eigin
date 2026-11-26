use super::*;
use crate::clock::ExecutionClock;

#[test]
fn dropping_a_pending_read_cancels_native_work_without_another_read() {
    block_on(async {
        let host = effects("primary", vec![]);
        let stream = host.streams.lock().unwrap()["primary"].clone();
        let (_sender, receiver) = futures::channel::oneshot::channel();
        *stream.pending.lock().unwrap() = Some(receiver);
        let mut request = InferenceRequest::open(options(), host.clone())
            .await
            .unwrap();
        assert!(request.next().now_or_never().is_none());
        assert!(stream.cancelled.load(Ordering::SeqCst));
        assert!(host.cancelled.lock().unwrap().contains(&0));
        assert!(matches!(
            request.next().await,
            Err(RequestError::Inference(InferenceError::Cancelled))
        ));
    });
}

#[test]
fn stop_after_delivery_cancels_without_waiting_for_the_consumer() {
    block_on(async {
        let host = effects("primary", vec![text("answer"), finish()]);
        let stream = host.streams.lock().unwrap()["primary"].clone();
        let mut request = InferenceRequest::open(options(), host).await.unwrap();
        assert_eq!(request.next().await.unwrap(), Some(text("answer")));
        request.cancellation().cancel();
        assert!(stream.cancelled.load(Ordering::SeqCst));
        assert!(matches!(
            request.next().await,
            Err(RequestError::Inference(InferenceError::Cancelled))
        ));
    });
}

#[test]
fn hedge_win_cancels_suspended_retry_preparation_without_dispatch() {
    block_on(async {
        let host = effects("hedge", vec![text("hedge answer"), finish()]);
        host.ranking.lock().unwrap().push_back("replacement".into());
        let (_release, wait) = futures::channel::oneshot::channel();
        host.preparing
            .lock()
            .unwrap()
            .insert("replacement".into(), wait);
        let mut input = options();
        input.hedge = Some(RequestHedge {
            model: "hedge".into(),
            delay_ms: 0,
        });
        let mut request = InferenceRequest::open(input, host.clone()).await.unwrap();
        assert_eq!(request.next().await.unwrap(), Some(text("hedge answer")));
        assert_eq!(request.attempts().winning_model(), "hedge");
        assert!(!request.attempts().retry_won());
        assert_eq!(*host.opens.lock().unwrap(), ["primary", "hedge"]);
        assert!(
            host.log
                .lock()
                .unwrap()
                .contains(&"prepare:replacement".into())
        );
        assert!(host.cancelled.lock().unwrap().contains(&2));
        assert!(host.log.lock().unwrap().contains(&"loser:primary".into()));
    });
}

#[test]
fn cancelled_pending_hedge_still_reports_its_open_failure() {
    block_on(async {
        let host = effects("primary", vec![finish()]);
        let primary = host.streams.lock().unwrap()["primary"].clone();
        let (speak, wait) = futures::channel::oneshot::channel();
        *primary.pending.lock().unwrap() = Some(wait);
        let (_open, wait) = futures::channel::oneshot::channel();
        host.opening.lock().unwrap().insert("hedge".into(), wait);
        let mut input = options();
        input.hedge = Some(RequestHedge {
            model: "hedge".into(),
            delay_ms: 0,
        });
        let mut request = InferenceRequest::open(input, host.clone()).await.unwrap();
        let mut next = Box::pin(request.next());
        assert!(futures::poll!(&mut next).is_pending());
        assert_eq!(*host.opens.lock().unwrap(), ["primary", "hedge"]);
        speak.send(Ok(Some(text("primary answer")))).unwrap();
        assert_eq!(next.await.unwrap(), Some(text("primary answer")));
        assert_eq!(request.next().await.unwrap(), Some(finish()));
        assert_eq!(request.next().await.unwrap(), None);
        assert!(host.log.lock().unwrap().contains(&"failure:hedge".into()));
    });
}

#[test]
fn cancellation_interrupts_a_suspended_preparation() {
    block_on(async {
        let host = Arc::new(Effects::default());
        let (_release, wait) = futures::channel::oneshot::channel();
        host.preparing
            .lock()
            .unwrap()
            .insert("primary".into(), wait);
        let mut request = InferenceRequest::open(options(), host.clone())
            .await
            .unwrap();
        let stop = request.cancellation();
        let mut next = Box::pin(request.next());
        assert!(futures::poll!(&mut next).is_pending());
        stop.cancel();
        assert!(host.cancelled.lock().unwrap().contains(&0));
        assert!(matches!(
            next.await,
            Err(RequestError::Inference(InferenceError::Cancelled))
        ));
        assert!(host.opens.lock().unwrap().is_empty());
    });
}

#[test]
fn due_ceiling_precedes_continuously_ready_candidate_work() {
    block_on(async {
        let host = effects("primary", vec![text(""), text("late answer")]);
        let mut input = options();
        input.ceiling_ms = 0;
        let mut request = InferenceRequest::open(input, host.clone()).await.unwrap();
        assert!(matches!(
            request.next().await,
            Err(RequestError::FirstEventTimeout)
        ));
        assert!(host.opens.lock().unwrap().is_empty());
    });
}

#[test]
fn stopping_or_dropping_reports_an_opening_hedge_without_further_consumption() {
    block_on(async {
        for drop_request in [false, true] {
            let host = effects("primary", vec![]);
            let primary = host.streams.lock().unwrap()["primary"].clone();
            let (_speak, wait) = futures::channel::oneshot::channel();
            *primary.pending.lock().unwrap() = Some(wait);
            let (_open, wait) = futures::channel::oneshot::channel();
            host.opening.lock().unwrap().insert("hedge".into(), wait);
            let mut input = options();
            input.hedge = Some(RequestHedge {
                model: "hedge".into(),
                delay_ms: 0,
            });
            let mut request = InferenceRequest::open(input, host.clone()).await.unwrap();
            let stop = request.cancellation();
            let mut next = Box::pin(request.next());
            assert!(futures::poll!(&mut next).is_pending());
            if drop_request {
                drop(next);
                drop(request);
            } else {
                stop.cancel();
                assert_eq!(
                    host.log
                        .lock()
                        .unwrap()
                        .iter()
                        .filter(|value| *value == "failure:hedge")
                        .count(),
                    1
                );
                assert!(matches!(
                    next.await,
                    Err(RequestError::Inference(InferenceError::Cancelled))
                ));
            }
            assert_eq!(
                host.log
                    .lock()
                    .unwrap()
                    .iter()
                    .filter(|value| *value == "failure:hedge")
                    .count(),
                1
            );
        }
    });
}

#[test]
fn cancellation_in_preparation_completion_prevents_initial_and_retry_dispatch() {
    block_on(async {
        for target in ["primary", "replacement"] {
            let host = Arc::new(Effects::default());
            host.ranking.lock().unwrap().push_back("replacement".into());
            let mut request = InferenceRequest::open(options(), host.clone())
                .await
                .unwrap();
            *host.cancel_on_prepare.lock().unwrap() = Some((target.into(), request.cancellation()));
            assert!(matches!(
                request.next().await,
                Err(RequestError::Inference(InferenceError::Cancelled))
            ));
            let expected: Vec<&str> = if target == "primary" {
                vec![]
            } else {
                vec!["primary"]
            };
            assert_eq!(*host.opens.lock().unwrap(), expected);
        }
    });
}

#[test]
fn dropping_local_open_cancels_pending_preparation() {
    block_on(async {
        let host = Arc::new(Effects::default());
        let (_release, wait) = futures::channel::oneshot::channel();
        host.preparing
            .lock()
            .unwrap()
            .insert("primary".into(), wait);
        let mut input = options();
        input.local = true;
        assert!(
            InferenceRequest::open(input, host.clone())
                .now_or_never()
                .is_none()
        );
        assert!(host.cancelled.lock().unwrap().contains(&0));
        assert!(host.opens.lock().unwrap().is_empty());
    });
}

#[test]
fn deadline_due_while_suspended_precedes_a_ready_read() {
    block_on(async {
        let host = effects("primary", vec![]);
        let primary = host.streams.lock().unwrap()["primary"].clone();
        let (speak, wait) = futures::channel::oneshot::channel();
        *primary.pending.lock().unwrap() = Some(wait);
        let mut input = options();
        input.ceiling_ms = 100;
        let clock = Arc::new(crate::clock::testing::ManualClock::default());
        let mut request =
            InferenceRequest::open_with_clock(input, host, clock.now(), clock.clone())
                .await
                .unwrap();
        let mut next = Box::pin(request.next());
        assert!(futures::poll!(&mut next).is_pending());
        clock.advance(std::time::Duration::from_millis(110));
        speak.send(Ok(Some(text("late answer")))).unwrap();
        assert!(matches!(next.await, Err(RequestError::FirstEventTimeout)));
    });
}
