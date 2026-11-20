use crate::{agent::*, conversation::ConversationMessage, inference::InferenceToolCall};

fn prose(text: &str) -> ConversationMessage {
    ConversationMessage {
        role: "assistant".into(),
        content: Some(text.into()),
        ..Default::default()
    }
}
fn batch(ids: &[&str]) -> ConversationMessage {
    ConversationMessage {
        tool_calls: Some(
            ids.iter()
                .map(|id| InferenceToolCall {
                    id: (*id).into(),
                    kind: "function".into(),
                    name: "action".into(),
                    arguments: "{}".into(),
                })
                .collect(),
        ),
        ..prose("working")
    }
}
fn result(id: &str) -> ConversationMessage {
    ConversationMessage {
        role: "tool".into(),
        tool_call_id: Some(id.into()),
        content: Some("done".into()),
        ..Default::default()
    }
}

#[test]
fn stopped_cloud_batch_retains_results_and_checkpoint_reads_are_observational() {
    let output = AgentTurnOutput::new();
    let draft = output.begin_draft().unwrap();
    output.update_draft("working".into()).unwrap();
    output.begin_tools().unwrap();
    let assistant = output.record_batch(batch(&["a", "b"])).unwrap();
    assert_eq!(assistant.origin, TurnOutputOrigin::Recorded { id: draft });
    assert_eq!(output.checkpoint().len(), 3);
    let completed = output.record_result(result("a")).unwrap();
    let checkpoint = output.checkpoint();
    assert_eq!(checkpoint.len(), 3);
    assert_eq!(checkpoint[1], completed);
    assert_eq!(checkpoint[2].message.tool_call_id.as_deref(), Some("b"));
    assert_eq!(checkpoint, output.checkpoint());
    assert_eq!(output.output(), vec![assistant, completed]);
    assert_eq!(output.retained_output(), output.output());
}

#[test]
fn inline_exchanges_leave_prose_active_and_final_identity_unchanged() {
    let output = AgentTurnOutput::new();
    let draft = output.begin_draft().unwrap();
    output.update_draft("before".into()).unwrap();
    assert_eq!(output.checkpoint().len(), 1);
    for id in ["a", "b"] {
        output
            .record_inline_exchange(vec![batch(&[id]), result(id)])
            .unwrap();
    }
    output.update_draft("before and after".into()).unwrap();
    let checkpoint = output.checkpoint();
    assert_eq!(checkpoint.len(), 5);
    assert_eq!(
        checkpoint[4].origin,
        TurnOutputOrigin::Recorded { id: draft }
    );
    assert_eq!(output.output().len(), 4);
    output.finish(Some(prose("before and after"))).unwrap();
    assert_eq!(output.checkpoint(), checkpoint);
    assert_eq!(output.output(), checkpoint);
    assert_eq!(output.retained_output().len(), 4);
}

#[test]
fn interrupted_prose_seals_once_and_recovery_gets_a_new_identity() {
    let output = AgentTurnOutput::new();
    let draft = output.begin_draft().unwrap();
    output.update_draft("partial".into()).unwrap();
    let checkpoint = output.checkpoint();
    let retained = output.retain_interrupted_prose().unwrap().unwrap();
    assert_eq!(retained.origin, TurnOutputOrigin::Recorded { id: draft });
    assert!(output.retain_interrupted_prose().unwrap().is_none());
    assert_eq!(output.checkpoint(), checkpoint);
    let next = output.begin_draft().unwrap();
    assert_ne!(next, draft);
    output.update_draft("recovered".into()).unwrap();
    assert_eq!(output.checkpoint().len(), 2);
    output.finish(Some(prose("recovered"))).unwrap();
    assert_eq!(output.output().len(), 2);
    assert_eq!(output.retained_output(), vec![retained]);
}

#[test]
fn invalid_inputs_do_not_partially_record_output() {
    let output = AgentTurnOutput::new();
    assert_eq!(
        output.update_draft("missing draft".into()),
        Err(RoundError::InvalidPhase)
    );
    output.begin_draft().unwrap();
    assert_eq!(
        output.record_batch(prose("no calls")),
        Err(RoundError::InvalidPhase)
    );
    assert_eq!(
        output.record_result(prose("not a result")),
        Err(RoundError::InvalidPhase)
    );
    assert_eq!(
        output.record_inline_exchange(vec![batch(&["a"])]),
        Err(RoundError::InvalidPhase)
    );
    assert!(output.output().is_empty());
    output.finish(None).unwrap();
    assert!(output.checkpoint().is_empty());
    assert_eq!(
        output.finish(Some(prose("duplicate"))),
        Err(RoundError::InvalidPhase)
    );
    assert!(output.output().is_empty());
}

#[test]
fn sealed_drafts_and_batches_cannot_be_recorded_twice() {
    let output = AgentTurnOutput::new();
    output.begin_draft().unwrap();
    output.update_draft("partial".into()).unwrap();
    output.retain_interrupted_prose().unwrap().unwrap();
    let before = output.checkpoint();
    assert_eq!(
        output.finish(Some(prose("duplicate"))),
        Err(RoundError::InvalidPhase)
    );
    assert_eq!(output.output(), before);
    assert_eq!(output.checkpoint(), before);

    output.begin_draft().unwrap();
    output.record_batch(batch(&["a"])).unwrap();
    let before_output = output.output();
    let before_checkpoint = output.checkpoint();
    assert_eq!(
        output.record_batch(batch(&["a"])),
        Err(RoundError::InvalidPhase)
    );
    assert_eq!(output.output(), before_output);
    assert_eq!(output.checkpoint(), before_checkpoint);
}

#[test]
fn completed_output_rejects_draft_transitions_without_mutation() {
    for final_message in [Some(prose("answer")), None] {
        let output = AgentTurnOutput::new();
        output.begin_draft().unwrap();
        output.update_draft("answer".into()).unwrap();
        output.finish(final_message).unwrap();
        let recorded = output.output();
        let retained = output.retained_output();
        let checkpoint = output.checkpoint();
        let unchanged = || {
            assert_eq!(output.output(), recorded);
            assert_eq!(output.retained_output(), retained);
            assert_eq!(output.checkpoint(), checkpoint);
        };
        assert_eq!(output.begin_draft(), Err(RoundError::InvalidPhase));
        unchanged();
        assert_eq!(
            output.update_draft("replacement".into()),
            Err(RoundError::InvalidPhase)
        );
        unchanged();
        assert_eq!(output.begin_tools(), Err(RoundError::InvalidPhase));
        unchanged();
        assert_eq!(
            output.record_batch(batch(&["a"])),
            Err(RoundError::InvalidPhase)
        );
        unchanged();
        assert_eq!(
            output.retain_interrupted_prose(),
            Err(RoundError::InvalidPhase)
        );
        unchanged();
        assert_eq!(
            output.finish(Some(prose("replacement"))),
            Err(RoundError::InvalidPhase)
        );
        unchanged();
    }
}

#[test]
fn result_admission_remains_with_the_host_and_round() {
    let output = AgentTurnOutput::new();
    output.begin_draft().unwrap();
    output.finish(Some(prose("answer"))).unwrap();
    output.record_result(result("a")).unwrap();
    output
        .record_inline_exchange(vec![batch(&["b"]), result("b")])
        .unwrap();
    assert_eq!(output.output().len(), 4);
    assert_eq!(output.checkpoint(), output.output());
}
