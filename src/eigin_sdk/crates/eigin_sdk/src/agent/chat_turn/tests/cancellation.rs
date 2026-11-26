use super::*;

#[test]
fn stop_between_cloud_results_retains_completed_work_and_uncertainty() {
    block_on(async {
        let host = Arc::new(Host::default());
        host.scripts.lock().unwrap().push_back(batch(&["a", "b"]));
        let (_release, wait) = oneshot::channel();
        host.waits.lock().unwrap().insert("b".into(), wait);
        let turn = operation(host.clone());
        let mut run = turn.run().boxed();
        assert!(futures::poll!(&mut run).is_pending());
        let stopped = turn.stop();
        assert_eq!(stopped.len(), 3);
        assert_eq!(stopped[1].message.content.as_deref(), Some("result"));
        assert_eq!(stopped[2].message.tool_call_id.as_deref(), Some("b"));
        assert_ne!(stopped[2].message.content.as_deref(), Some("result"));
        assert!(run.await.unwrap().is_empty());
        assert_eq!(turn.checkpoint(), stopped);
        assert_eq!(host.contexts.lock().unwrap().len(), 1);
    });
}

#[test]
fn dropping_run_closes_admission_before_cancellation_callback_reentry() {
    block_on(async {
        let host = Arc::new(Host::default());
        host.reenter_on_cancel.store(true, Ordering::SeqCst);
        host.scripts
            .lock()
            .unwrap()
            .push_back(Script::events(vec![text("answer"), finish()]));
        let (_release, wait) = oneshot::channel();
        *host.next_wait.lock().unwrap() = Some(wait);
        let turn = operation(host.clone());
        let mut run = turn.run();
        assert!(futures::poll!(&mut run).is_pending());
        drop(run);
        assert!(host.calls.lock().unwrap().is_empty());
        assert!(turn.checkpoint().is_empty());
        assert!(matches!(
            turn.run().await,
            Err(ChatTurnError::AlreadyStarted)
        ));
    });
}

#[test]
fn stop_rejects_late_inline_output_but_returns_executed_result() {
    block_on(async {
        let host = Arc::new(Host::default());
        host.local.store(true, Ordering::SeqCst);
        host.scripts
            .lock()
            .unwrap()
            .push_back(Script::events(vec![text("answer"), finish()]));
        let (_read, wait) = oneshot::channel();
        *host.next_wait.lock().unwrap() = Some(wait);
        let (complete, wait) = oneshot::channel();
        host.waits.lock().unwrap().insert("late".into(), wait);
        let turn = operation(host.clone());
        let mut run = turn.run();
        assert!(futures::poll!(&mut run).is_pending());
        assert!(matches!(
            turn.run().await,
            Err(ChatTurnError::AlreadyStarted)
        ));
        let inline = host.inline.lock().unwrap()[0].clone();
        assert!(!inline.execute(call("completed")).await.is_error);
        let mut late = inline.execute(call("late")).boxed();
        assert!(futures::poll!(&mut late).is_pending());
        let checkpoint = turn.stop();
        assert_eq!(checkpoint.len(), 2);
        assert!(run.await.unwrap().is_empty());
        complete.send(()).unwrap();
        let result = late.await;
        assert!(!result.is_error);
        assert_eq!(result.content, "result");
        assert_eq!(turn.checkpoint(), checkpoint);
        assert!(inline.execute(call("after-stop")).await.is_error);
        assert_eq!(*host.calls.lock().unwrap(), ["completed", "late"]);
    });
}

#[test]
fn stop_wakes_suspended_context_and_presentation_without_late_output() {
    block_on(async {
        for preparing in [false, true] {
            let host = Arc::new(Host::default());
            host.scripts
                .lock()
                .unwrap()
                .push_back(Script::events(vec![text("answer"), finish()]));
            let (late, wait) = oneshot::channel();
            if preparing {
                *host.prepare_wait.lock().unwrap() = Some(wait);
            } else {
                *host.drain_wait.lock().unwrap() = Some(wait);
            }
            let turn = operation(host.clone());
            let mut run = turn.run();
            assert!(futures::poll!(&mut run).is_pending());
            let checkpoint = turn.stop();
            assert_eq!(checkpoint.len(), usize::from(!preparing));
            assert!(run.await.unwrap().is_empty());
            assert!(late.send(()).is_err());
            assert_eq!(turn.checkpoint(), checkpoint);
        }
    });
}

#[test]
fn request_cleanup_rejects_inline_reentry_on_eof_and_terminal_failure() {
    block_on(async {
        for local in [false, true] {
            for failed in [false, true] {
                let host = Arc::new(Host::default());
                host.local.store(local, Ordering::SeqCst);
                host.reenter_on_cancel.store(true, Ordering::SeqCst);
                host.scripts.lock().unwrap().push_back(Script {
                    error: failed.then_some(RequestError::InvalidToolCall),
                    ..Script::events(if failed {
                        vec![text("partial")]
                    } else {
                        vec![text("answer"), finish()]
                    })
                });
                let turn = operation(host.clone());
                let result = turn.run().await;
                assert_eq!(result.is_err(), failed);
                assert!(host.calls.lock().unwrap().is_empty());
                assert_eq!(turn.checkpoint().len(), 1);
                assert_eq!(host.contexts.lock().unwrap().len(), 1);
            }
        }
    });
}

#[test]
fn terminal_reporting_distinguishes_stop_cancel_and_abandoned_work() {
    block_on(async {
        for action in ["stop", "cancel", "drop"] {
            let host = Arc::new(Host::default());
            host.scripts
                .lock()
                .unwrap()
                .push_back(Script::events(vec![text("answer"), finish()]));
            let (_release, wait) = oneshot::channel();
            *host.next_wait.lock().unwrap() = Some(wait);
            let turn = operation(host.clone());
            let mut run = turn.run();
            assert!(futures::poll!(&mut run).is_pending());
            match action {
                "stop" => {
                    turn.stop();
                    assert!(run.await.unwrap().is_empty());
                }
                "cancel" => {
                    turn.cancel();
                    assert!(run.await.unwrap().is_empty());
                }
                _ => drop(run),
            }
            let reports = host.reports.lock().unwrap();
            if action == "cancel" {
                assert!(matches!(
                    reports.as_slice(),
                    [crate::inference::routing::RoutingResult::Cancelled]
                ));
            } else {
                assert!(reports.is_empty(), "{action}");
            }
        }
    });
}
