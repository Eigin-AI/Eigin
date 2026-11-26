use super::*;

#[test]
fn cloud_tools_automatically_continue_with_results_and_updated_tools() {
    block_on(async {
        let host = Arc::new(Host::default());
        host.scripts.lock().unwrap().extend([
            batch(&["a", "b"]),
            Script::events(vec![text("answer"), finish()]),
        ]);
        let turn = operation(host.clone());
        let output = turn.run().boxed().await.unwrap();
        assert_eq!(*host.calls.lock().unwrap(), ["a", "b"]);
        assert_eq!(
            output
                .iter()
                .map(|entry| entry.message.role.as_str())
                .collect::<Vec<_>>(),
            ["assistant", "tool", "tool", "assistant"]
        );
        assert_eq!(
            output.last().unwrap().message.content.as_deref(),
            Some("answer")
        );
        let contexts = host.contexts.lock().unwrap();
        assert_eq!(contexts.len(), 2);
        assert_eq!(contexts[1].output.len(), 3);
        assert_eq!(contexts[1].tools.as_ref().unwrap()[0].name, "refreshed");
        assert_eq!(turn.rounds_executed(), 2);
        assert_eq!(turn.retained_output().len(), 3);
    });
}

#[test]
fn local_inline_result_resumes_same_request_and_is_recorded_once() {
    block_on(async {
        let host = Arc::new(Host::default());
        host.local.store(true, Ordering::SeqCst);
        host.scripts.lock().unwrap().push_back(Script {
            inline: vec![call("inline")],
            ..Script::events(vec![text("answer"), finish()])
        });
        let turn = operation(host.clone());
        let output = turn.run().await.unwrap();
        assert_eq!(
            output
                .iter()
                .map(|entry| entry.message.role.as_str())
                .collect::<Vec<_>>(),
            ["assistant", "tool", "assistant"]
        );
        assert_eq!(*host.calls.lock().unwrap(), ["inline"]);
        assert_eq!(host.contexts.lock().unwrap().len(), 1);
        assert_eq!(host.refreshes.load(Ordering::SeqCst), 0);
        let inline = host.inline.lock().unwrap()[0].clone();
        assert!(inline.execute(call("stale")).await.is_error);
        assert_eq!(turn.checkpoint(), output);
    });
}

#[test]
fn final_permitted_tool_batch_executes_and_refreshes_before_limit() {
    block_on(async {
        let host = Arc::new(Host::default());
        for _ in 0..40 {
            host.scripts.lock().unwrap().push_back(batch(&["call"]));
        }
        let turn = operation(host.clone());
        assert_eq!(turn.run().await.unwrap().len(), 80);
        assert_eq!(turn.rounds_executed(), 40);
        assert_eq!(host.refreshes.load(Ordering::SeqCst), 40);
        assert_eq!(host.calls.lock().unwrap().len(), 40);
    });
}

#[test]
fn interruption_and_missing_reply_share_recovery_allowance() {
    block_on(async {
        let host = Arc::new(Host::default());
        host.scripts.lock().unwrap().extend([
            Script {
                error: Some(InferenceError::Interrupted.into()),
                ..Script::events(vec![text("partial")])
            },
            Script::events(vec![text(" "), finish()]),
        ]);
        let turn = operation(host.clone());
        assert!(matches!(turn.run().await, Err(ChatTurnError::MissingReply)));
        let contexts = host.contexts.lock().unwrap();
        assert_eq!(contexts.len(), 2);
        assert_eq!(
            contexts[1].continuation,
            Some(crate::agent::TurnContinuation::Interrupted)
        );
        assert_eq!(
            contexts[1].output[0].message.content.as_deref(),
            Some("partial")
        );
    });
}

#[test]
fn local_interruption_does_not_start_recovery_request() {
    block_on(async {
        let host = Arc::new(Host::default());
        host.local.store(true, Ordering::SeqCst);
        host.scripts.lock().unwrap().push_back(Script {
            error: Some(InferenceError::Interrupted.into()),
            ..Script::events(vec![text("partial")])
        });
        let turn = operation(host.clone());
        assert!(matches!(
            turn.run().await,
            Err(ChatTurnError::Request(RequestError::Inference(
                InferenceError::Interrupted
            )))
        ));
        assert_eq!(host.contexts.lock().unwrap().len(), 1);
        assert_eq!(
            turn.checkpoint()[0].message.content.as_deref(),
            Some("partial")
        );
    });
}

#[test]
fn explicit_termination_after_tools_skips_refresh_and_another_request() {
    block_on(async {
        let host = Arc::new(Host::default());
        host.terminate.store(true, Ordering::SeqCst);
        host.scripts.lock().unwrap().push_back(batch(&["a", "b"]));
        let turn = operation(host.clone());
        assert_eq!(turn.run().await.unwrap().len(), 3);
        assert_eq!(*host.calls.lock().unwrap(), ["a", "b"]);
        assert_eq!(host.refreshes.load(Ordering::SeqCst), 0);
        assert_eq!(host.contexts.lock().unwrap().len(), 1);
    });
}
