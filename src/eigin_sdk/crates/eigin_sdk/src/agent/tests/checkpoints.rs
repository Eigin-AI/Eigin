use crate::{agent::*, conversation::ConversationMessage, inference::*};

fn call(id: &str) -> InferenceToolCall {
    InferenceToolCall {
        id: id.into(),
        kind: "function".into(),
        name: "action".into(),
        arguments: "{}".into(),
    }
}
fn batch(ids: &[&str]) -> ConversationMessage {
    ConversationMessage {
        role: "assistant".into(),
        content: Some("working".into()),
        tool_calls: Some(ids.iter().map(|id| call(id)).collect()),
        ..Default::default()
    }
}
fn result(id: &str, content: &str) -> ConversationMessage {
    ConversationMessage {
        role: "tool".into(),
        tool_call_id: Some(id.into()),
        content: Some(content.into()),
        ..Default::default()
    }
}
fn progress(count: u64) -> CheckpointProgress {
    CheckpointProgress {
        retained_count: count,
        ..Default::default()
    }
}

#[test]
fn partial_prose_uses_retained_identity_and_execution_facts() {
    assert!(agent_build_checkpoint(vec![], progress(0)).is_empty());
    let p = CheckpointProgress {
        partial_content: "partial".into(),
        ..progress(0)
    };
    let snapshot = agent_build_checkpoint(vec![], p.clone());
    assert_eq!(snapshot.len(), 1);
    assert_eq!(snapshot[0].origin, CheckpointOrigin::PartialProse);
    assert_eq!(snapshot[0].message.content.as_deref(), Some("partial"));
    assert!(snapshot[0].message.tool_calls.is_none());
    assert!(
        agent_build_checkpoint(
            vec![],
            CheckpointProgress {
                is_executing_tools: true,
                ..p.clone()
            }
        )
        .is_empty()
    );
    let prose = snapshot[0].message.clone();
    let retained = agent_build_checkpoint(
        vec![prose.clone()],
        CheckpointProgress {
            retained_count: 1,
            current_message_index: Some(0),
            ..p.clone()
        },
    );
    assert_eq!(retained.len(), 1);
    assert_eq!(retained[0].origin, CheckpointOrigin::Produced { index: 0 });
    // A message outside the retained prefix does not suppress partial prose.
    assert_eq!(
        agent_build_checkpoint(
            vec![prose],
            CheckpointProgress {
                current_message_index: Some(0),
                ..p
            }
        ),
        snapshot
    );
}

#[test]
fn closes_batches_before_execution_and_after_each_completed_result() {
    for completed in 0..=2 {
        let mut produced = vec![batch(&["a", "b"])];
        for id in ["a", "b"].iter().take(completed) {
            produced.push(result(id, "completed"));
        }
        let p = CheckpointProgress {
            is_executing_tools: true,
            partial_content: "working".into(),
            ..progress(produced.len() as u64)
        };
        let snapshot = agent_build_checkpoint(produced.clone(), p.clone());
        assert_eq!(snapshot.len(), 3);
        assert_eq!(snapshot, agent_build_checkpoint(produced.clone(), p));
        for (index, value) in produced.iter().enumerate() {
            assert_eq!(&snapshot[index].message, value);
        }
        for entry in &snapshot[produced.len()..] {
            assert_eq!(entry.origin, CheckpointOrigin::InterruptedTool);
            assert_eq!(entry.message.name.as_deref(), Some("action"));
            assert_eq!(
                entry.message.content.as_deref(),
                Some(
                    "Tool execution was interrupted. Completion is unknown; do not repeat the action without checking its state."
                )
            );
        }
    }
}

#[test]
fn preserves_multiple_results_and_existing_global_unicode_id_matching() {
    let messages = vec![
        batch(&["é"]),
        result("e\u{301}", "first"),
        result("é", "second"),
        batch(&["é", "b"]),
    ];
    let snapshot = agent_build_checkpoint(messages.clone(), progress(4));
    assert_eq!(snapshot.len(), 5);
    assert_eq!(snapshot[4].message.tool_call_id.as_deref(), Some("b"));
    assert_eq!(
        snapshot[..4]
            .iter()
            .map(|entry| entry.message.clone())
            .collect::<Vec<_>>(),
        messages
    );
    // Only the latest batch is closed, even for a caller-supplied incomplete earlier batch.
    let snapshot = agent_build_checkpoint(vec![batch(&["old"]), batch(&["new"])], progress(2));
    assert_eq!(snapshot.len(), 3);
    assert_eq!(snapshot[2].message.tool_call_id.as_deref(), Some("new"));
}

#[test]
fn done_returns_every_value_unchanged_and_prefix_is_bounded() {
    let mut message = batch(&["a"]);
    message.source_index = Some(42);
    message.is_compaction_summary = true;
    message.compaction_retained_message_count = Some(7);
    message.attachments = Some(vec![crate::conversation::ConversationAttachmentReference {
        id: "attachment".into(),
        kind: "image".into(),
        mime_type: "image/png".into(),
        width: Some(100),
        height: Some(200),
        byte_count: 300,
    }]);
    message.provider_metadata = Some([("signature".into(), "opaque".into())].into());
    message.reasoning_history = Some(InferenceReasoningHistory {
        origin: InferenceReasoningOrigin {
            provider_id: "provider".into(),
            endpoint: "endpoint".into(),
            model: "model".into(),
        },
        format: "opaque".into(),
        payload: "payload".into(),
        visible_text: "thought".into(),
        additional_input_tokens: 12,
    });
    let snapshot = agent_build_checkpoint(
        vec![message.clone()],
        CheckpointProgress {
            is_done: true,
            partial_content: "ignored".into(),
            ..progress(0)
        },
    );
    assert_eq!(snapshot.len(), 1);
    assert_eq!(snapshot[0].message, message);
    assert_eq!(snapshot[0].origin, CheckpointOrigin::Produced { index: 0 });
    let snapshot = agent_build_checkpoint(vec![message.clone()], progress(u64::MAX));
    assert_eq!(snapshot[0].message, message);
    assert_eq!(snapshot.len(), 2);
}

#[test]
fn round_inline_exchanges_are_retained_without_inventing_pending_calls() {
    let round = AgentRound::new();
    round
        .accept_event(InferenceEvent::ContentDelta {
            text: "prose".into(),
        })
        .unwrap();
    let before = agent_build_checkpoint(vec![], progress(0));
    assert!(before.is_empty());
    let exchange = round
        .record_inline_exchange(
            call("inline"),
            RoundToolResult {
                tool_call_id: "inline".into(),
                content: "done".into(),
            },
        )
        .unwrap();
    let snapshot = agent_build_checkpoint(
        exchange.clone(),
        CheckpointProgress {
            partial_content: round.partial_content(),
            ..progress(2)
        },
    );
    assert_eq!(snapshot.len(), 3);
    assert_eq!(snapshot[0].message, exchange[0]);
    assert_eq!(snapshot[1].message, exchange[1]);
    assert_eq!(snapshot[2].origin, CheckpointOrigin::PartialProse);
}
