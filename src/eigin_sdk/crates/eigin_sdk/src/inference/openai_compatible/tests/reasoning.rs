use super::*;

fn origin() -> InferenceReasoningOrigin {
    InferenceReasoningOrigin {
        provider_id: "provider-1".into(),
        endpoint: "https://api.mistral.ai/v1".into(),
        model: "test-model".into(),
    }
}
fn thinking(text: &str, closed: Option<bool>) -> Value {
    let mut part = json!({"type":"thinking","thinking":[{"type":"text","text":text}]});
    if let Some(closed) = closed {
        part["closed"] = json!(closed);
    }
    part
}

#[test]
fn reasoning_round_trip_is_origin_and_visible_text_scoped() {
    for relay in [false, true] {
        for tool_round in [false, true] {
            let mut start = thinking("private thought", Some(false));
            start["signature"] = json!("opaque-signature");
            let body = sse(&[
                chunk(json!({"content":[start]}), None),
                chunk(
                    json!({"content":[thinking("", Some(true)), {"type":"text","text":"Answer"}]}),
                    None,
                ),
                chunk(json!({"content":" continues"}), None),
                chunk(
                    if tool_round {
                        json!({"tool_calls":[{"index":0,"id":"call_1","function":{"name":"lookup","arguments":"{}"}}]})
                    } else {
                        json!({})
                    },
                    Some(if tool_round { "tool_calls" } else { "stop" }),
                ),
            ]);
            let base = if relay {
                "https://relay.test/v1"
            } else {
                "https://api.mistral.ai/v1"
            };
            let (provider, _) = provider(base, 200, body);
            let mut input = input();
            input.model_family = Some(InferenceModelFamily::Mistral);
            input.is_relay = relay;
            input.reasoning_origin = Some(origin());
            let (events, result) = collect(&provider, input.clone());
            result.unwrap();
            let history = events
                .iter()
                .find_map(|e| match e {
                    InferenceEvent::ReasoningHistory { history } => Some(history.clone()),
                    _ => None,
                })
                .unwrap();
            assert_eq!(history.visible_text, "Answer continues");
            let history_index = events
                .iter()
                .position(|e| matches!(e, InferenceEvent::ReasoningHistory { .. }))
                .unwrap();
            if tool_round {
                assert!(matches!(
                    events[history_index + 1],
                    InferenceEvent::ToolCall { .. }
                ));
            }
            for variation in 0..6 {
                let (replay, transport) = super::provider(base, 200, finished());
                let mut replay_input = input.clone();
                let mut saved = history.clone();
                match variation {
                    1 => {
                        replay_input.reasoning_origin.as_mut().unwrap().provider_id = "other".into()
                    }
                    2 => {
                        replay_input.reasoning_origin.as_mut().unwrap().model = "other-model".into()
                    }
                    3 => {
                        replay_input.reasoning_origin.as_mut().unwrap().endpoint =
                            "https://other.test/v1".into()
                    }
                    4 => saved.format = "unsupported-format-v1".into(),
                    _ => {}
                }
                replay_input.messages = vec![InferenceMessage {
                    role: "assistant".into(),
                    content: Some(
                        if variation == 5 {
                            "edited"
                        } else {
                            "Answer continues"
                        }
                        .into(),
                    ),
                    reasoning_history: Some(saved),
                    ..Default::default()
                }];
                collect(&replay, replay_input).1.unwrap();
                assert_eq!(
                    request_body(&transport)
                        .to_string()
                        .contains("opaque-signature"),
                    variation == 0
                );
            }
        }
    }
}

#[test]
fn incomplete_and_invalid_reasoning_is_never_replayable() {
    for variant in [
        "open",
        "omitted-close",
        "bad-transition",
        "conflict",
        "unsupported",
        "malformed",
        "length",
        "eof",
    ] {
        let mut parts = vec![chunk(
            json!({"content":[thinking("first",Some(false))]}),
            None,
        )];
        match variant {
            "omitted-close" => {
                parts.push(chunk(json!({"content":[thinking(" second",None)]}), None))
            }
            "bad-transition" => parts.push(chunk(json!({"content":"answer"}), None)),
            "conflict" => {
                let mut one = thinking("second", None);
                one["signature"] = json!("one");
                let mut two = thinking("third", Some(true));
                two["signature"] = json!("two");
                parts.push(chunk(json!({"content":[one,two]}), None));
            }
            "unsupported" => parts.push(chunk(json!({"content":[{"type":"image"}]}), None)),
            "malformed" => parts.push(json!({"bad":"chunk"})),
            _ => {}
        }
        if variant != "eof" {
            parts.push(chunk(
                json!({}),
                Some(if variant == "length" {
                    "length"
                } else {
                    "stop"
                }),
            ));
        }
        let (provider, _) = provider("https://api.mistral.ai/v1", 200, sse(&parts));
        let mut input = input();
        input.reasoning_origin = Some(origin());
        let (events, _) = collect(&provider, input);
        assert!(
            !events
                .iter()
                .any(|e| matches!(e, InferenceEvent::ReasoningHistory { .. })),
            "{variant}"
        );
    }
}

#[test]
fn explicitly_closed_thinking_merges_omitted_intermediate_flags() {
    let (provider, _) = provider(
        "https://api.mistral.ai/v1",
        200,
        sse(&[
            chunk(json!({"content":[thinking("first",Some(false))]}), None),
            chunk(json!({"content":[thinking(" second",None)]}), None),
            chunk(
                json!({"content":[thinking(" third",Some(true))]}),
                Some("stop"),
            ),
        ]),
    );
    let mut input = input();
    input.reasoning_origin = Some(origin());
    let (events, result) = collect(&provider, input);
    result.unwrap();
    let InferenceEvent::ReasoningHistory { history } = &events[0] else {
        panic!("missing history")
    };
    let payload: Value = serde_json::from_slice(&history.payload).unwrap();
    assert_eq!(payload.as_array().unwrap().len(), 1);
    assert_eq!(payload[0]["closed"], true);
    assert_eq!(payload[0]["thinking"].as_array().unwrap().len(), 3);
}
