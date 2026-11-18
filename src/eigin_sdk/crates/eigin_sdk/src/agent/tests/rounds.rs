use crate::agent::*;
use crate::inference::*;

fn call(id: &str, arguments: &str) -> InferenceToolCall {
    InferenceToolCall {
        id: id.into(),
        kind: "function".into(),
        name: "lookup".into(),
        arguments: arguments.into(),
    }
}
fn result(id: &str) -> RoundToolResult {
    RoundToolResult {
        tool_call_id: id.into(),
        content: "result".into(),
    }
}
fn text(round: &AgentRound, value: &str) {
    round
        .accept_event(InferenceEvent::ContentDelta { text: value.into() })
        .unwrap();
}
fn finish(round: &AgentRound, reason: InferenceFinishReason) -> Result<RoundOutcome, RoundError> {
    round
        .accept_event(InferenceEvent::Finished { reason })
        .unwrap();
    round.finish_stream()
}

#[test]
fn text_is_accumulated_and_empty_output_is_explicit() {
    let round = AgentRound::new();
    text(&round, "hello ");
    text(&round, "world");
    assert_eq!(round.partial_content(), "hello world");
    let RoundOutcome::Reply { message } = finish(&round, InferenceFinishReason::Stop).unwrap()
    else {
        panic!()
    };
    assert_eq!(message.content.as_deref(), Some("hello world"));
    assert_eq!(
        finish(&AgentRound::new(), InferenceFinishReason::Stop).unwrap(),
        RoundOutcome::Empty
    );
}

#[test]
fn batch_results_are_sequential_and_preserve_supplied_ids() {
    let round = AgentRound::new();
    text(&round, "checking");
    for id in ["a", "b"] {
        round
            .accept_event(InferenceEvent::ToolCall {
                call: call(id, "{}"),
            })
            .unwrap();
    }
    assert!(round.has_tool_calls());
    let RoundOutcome::Tools { assistant, calls } =
        finish(&round, InferenceFinishReason::ToolCalls).unwrap()
    else {
        panic!()
    };
    assert_eq!(assistant.content.as_deref(), Some("checking"));
    assert_eq!(calls.len(), 2);
    assert_eq!(
        round
            .record_result(result("supplied"))
            .unwrap()
            .tool_call_id
            .as_deref(),
        Some("supplied")
    );
    assert_eq!(
        round.record_result(result("b")).unwrap().name.as_deref(),
        Some("lookup")
    );
    assert_eq!(
        round.record_result(result("extra")),
        Err(RoundError::InvalidPhase)
    );
}

#[test]
fn entire_batch_must_be_valid_before_execution() {
    for invalid in ["[]", "null", "1", "{broken"] {
        let round = AgentRound::new();
        round
            .accept_event(InferenceEvent::ToolCall {
                call: call("a", "{}"),
            })
            .unwrap();
        round
            .accept_event(InferenceEvent::ToolCall {
                call: call("b", invalid),
            })
            .unwrap();
        assert_eq!(
            finish(&round, InferenceFinishReason::ToolCalls),
            Err(RoundError::InvalidToolCall)
        );
        assert_eq!(
            round.record_result(result("a")),
            Err(RoundError::InvalidPhase)
        );
    }
}

#[test]
fn interrupted_round_exposes_only_partial_prose_and_cannot_execute() {
    let round = AgentRound::new();
    text(&round, "partial");
    round
        .accept_event(InferenceEvent::ToolCall {
            call: call("a", "{}"),
        })
        .unwrap();
    assert_eq!(round.finish_stream(), Err(RoundError::Interrupted));
    assert_eq!(round.partial_content(), "partial");
    assert_eq!(
        round.record_result(result("a")),
        Err(RoundError::InvalidPhase)
    );
    assert_eq!(round.finish_stream(), Err(RoundError::InvalidPhase));
    assert_eq!(AgentRound::new().partial_content(), "");
}

#[test]
fn inline_exchanges_do_not_consume_prose_or_finish_generation() {
    let round = AgentRound::new();
    text(&round, "before");
    for id in ["a", "b"] {
        let messages = round
            .record_inline_exchange(call(id, "{}"), result(id))
            .unwrap();
        assert_eq!(messages.len(), 2);
        assert_eq!(messages[0].content, None);
        assert_eq!(messages[1].tool_call_id.as_deref(), Some(id));
    }
    text(&round, " after");
    let RoundOutcome::Reply { message } = finish(&round, InferenceFinishReason::Stop).unwrap()
    else {
        panic!()
    };
    assert_eq!(message.content.as_deref(), Some("before after"));
    assert_eq!(
        round.record_inline_exchange(call("c", "{}"), result("c")),
        Err(RoundError::InvalidPhase)
    );
}

#[test]
fn metadata_and_reasoning_use_last_event_and_preserve_transcript_rules() {
    for tools in [false, true] {
        let round = AgentRound::new();
        for value in ["first", "last"] {
            round
                .accept_event(InferenceEvent::ProviderMetadata {
                    values: [("key".into(), value.into())].into(),
                })
                .unwrap();
            round
                .accept_event(InferenceEvent::ReasoningHistory {
                    history: InferenceReasoningHistory {
                        origin: InferenceReasoningOrigin {
                            provider_id: "provider".into(),
                            endpoint: "endpoint".into(),
                            model: "model".into(),
                        },
                        format: "opaque".into(),
                        payload: value.as_bytes().to_vec(),
                        visible_text: String::new(),
                        additional_input_tokens: 1,
                    },
                })
                .unwrap();
        }
        if tools {
            round
                .accept_event(InferenceEvent::ToolCall {
                    call: call("a", "{}"),
                })
                .unwrap();
        }
        let outcome = finish(
            &round,
            if tools {
                InferenceFinishReason::ToolCalls
            } else {
                InferenceFinishReason::Stop
            },
        )
        .unwrap();
        let message = match outcome {
            RoundOutcome::Tools { assistant, .. } => assistant,
            RoundOutcome::Reply { message } => message,
            _ => panic!(),
        };
        assert_eq!(message.reasoning_history.unwrap().payload, b"last");
        assert_eq!(message.provider_metadata.is_some(), tools);
        if tools {
            assert_eq!(message.provider_metadata.unwrap()["key"], "last");
        }
    }
}

#[test]
fn stop_ignores_calls_and_tool_finish_without_calls_is_a_reply() {
    let round = AgentRound::new();
    text(&round, "answer");
    round
        .accept_event(InferenceEvent::ToolCall {
            call: call("", "invalid"),
        })
        .unwrap();
    assert!(matches!(
        finish(&round, InferenceFinishReason::Stop),
        Ok(RoundOutcome::Reply { .. })
    ));
    let round = AgentRound::new();
    text(&round, "answer");
    assert!(matches!(
        finish(&round, InferenceFinishReason::ToolCalls),
        Ok(RoundOutcome::Reply { .. })
    ));
}
