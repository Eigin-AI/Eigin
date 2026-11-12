use super::super::types::*;
use futures::executor::block_on;
use serde_json::json;
mod cancellation;
mod support;
use support::*;

fn finish(reason: &str) -> String {
    sse(&[
        json!({"type":"message_delta","delta":{"stop_reason":reason}}),
        json!({"type":"message_stop"}),
    ])
}
fn message(role: &str, text: &str) -> InferenceMessage {
    InferenceMessage {
        role: role.into(),
        content: Some(text.into()),
        ..Default::default()
    }
}

#[test]
fn converts_messages_tools_images_and_cache_defaults() {
    let (provider, transport) = provider("https://example.test/v1/", 200, finish("end_turn"));
    let mut input = input();
    input.prompt_cache_key = Some("ignored".into());
    input.reasoning_effort = Some("high".into());
    input.messages = vec![
        message("system", "one"),
        message("system", "two"),
        InferenceMessage {
            images: vec![InferenceImage {
                mime_type: "image/png".into(),
                bytes: vec![1, 2, 3],
            }],
            ..message("user", "hi")
        },
        InferenceMessage {
            tool_calls: Some(vec![InferenceToolCall {
                id: "c".into(),
                kind: "function".into(),
                name: "search".into(),
                arguments: "[]".into(),
            }]),
            ..message("assistant", "looking")
        },
        InferenceMessage {
            tool_call_id: Some("c".into()),
            ..message("tool", "result")
        },
        message("tool", "second"),
        message("developer", "fallback"),
    ];
    input.tools = Some(vec![InferenceToolDefinition {
        name: "search".into(),
        description: "Search".into(),
        parameters_json: "{\"type\":\"object\"}".into(),
    }]);
    collect(&provider, input).1.unwrap();
    let body = request_body(&transport);
    assert_eq!(body["system"], "one\n\ntwo");
    assert_eq!(
        body["messages"][0]["content"],
        json!([
        {"type":"image","source":{"type":"base64","media_type":"image/png","data":"AQID"}},
        {"type":"text","text":"hi"}])
    );
    assert_eq!(
        body["messages"][1]["content"][1],
        json!({"type":"tool_use","id":"c","name":"search","input":{}})
    );
    assert_eq!(
        body["messages"][2]["content"],
        json!([
        {"type":"tool_result","tool_use_id":"c","content":"result"},
        {"type":"tool_result","tool_use_id":"","content":"second"}])
    );
    assert_eq!(
        body["messages"][3],
        json!({"role":"user","content":"fallback"})
    );
    assert_eq!(body["tools"][0]["input_schema"], json!({"type":"object"}));
    assert_eq!(body["max_tokens"], 8192);
    assert_eq!(body["cache_control"], json!({"type":"ephemeral"}));
    assert_eq!(body["stream"], true);
    assert!(body.get("prompt_cache_key").is_none());
    assert!(body.get("reasoning").is_none());
    let requests = transport.requests.lock().unwrap();
    assert_eq!(requests[0].url, "https://example.test/v1/messages");
    assert_eq!(requests[0].headers["x-api-key"], "test-key");
    assert_eq!(requests[0].headers["anthropic-version"], "2023-06-01");
    assert!(!requests[0].headers.contains_key("authorization"));
}

#[test]
fn unloaded_attachments_preserve_text_blocks_and_empty_fallback() {
    let (provider, transport) = provider("https://example.test", 200, finish("stop_sequence"));
    let mut input = input();
    input.messages = vec![
        InferenceMessage {
            has_attachments: true,
            ..message("user", "text")
        },
        InferenceMessage {
            has_attachments: true,
            ..message("user", "")
        },
        message("assistant", ""),
    ];
    collect(&provider, input).1.unwrap();
    let body = request_body(&transport);
    assert_eq!(
        body["messages"][0]["content"],
        json!([{"type":"text","text":"text"}])
    );
    assert_eq!(body["messages"][1]["content"], "");
    assert_eq!(body["messages"][2]["content"], "");
    assert!(body.get("tools").is_none());
    assert!(body.get("system").is_none());
}

#[test]
fn discovery_sorts_and_validation_preserves_auth_only_failure() {
    let _lock = crate::diagnostics::delivery::tests::RECEIVER_TEST_LOCK
        .lock()
        .unwrap();
    let (p, t) = provider(
        "https://example.test/v1",
        200,
        r#"{"data":[{"id":"z"},{"id":"a"},{"id":"a"}]}"#,
    );
    assert_eq!(
        block_on(p.discovery().fetch_models()).unwrap(),
        vec!["a", "a", "z"]
    );
    assert_eq!(t.requests.lock().unwrap()[0].method, "GET");
    for status in [200, 400, 401, 403, 404, 429, 500] {
        let (p, t) = provider("https://example.test", status, "{}");
        let result = block_on(p.key_validation().validate_api_key("model".into()));
        if status == 401 || status == 403 {
            assert!(matches!(result,Err(InferenceError::Http{status:s,body:None}) if s == status));
        } else {
            result.unwrap();
        }
        assert_eq!(
            request_body(&t),
            json!({"model":"model","max_tokens":1,"cache_control":{"type":"ephemeral"},"messages":[{"role":"user","content":"hi"}],"stream":false})
        );
    }
    let (p, _) = provider("https://example.test", 200, "{}");
    assert!(matches!(
        block_on(p.discovery().fetch_models()),
        Err(InferenceError::InvalidData { .. })
    ));
    let (p, _) = provider("https://example.test", 500, "private");
    assert!(matches!(
        block_on(p.discovery().fetch_models()),
        Err(InferenceError::Http {
            status: 500,
            body: None
        })
    ));
}

#[test]
fn fragmented_typed_stream_delivers_text_tools_and_finish() {
    let body = sse(&[
        json!({"type":"message_start"}),
        json!({"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"héj"}}),
        json!({"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"c","name":"search"}}),
        json!({"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\"q\":"}}),
        json!({"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"1}"}}),
        json!({"type":"content_block_stop","index":1}),
    ]) + &finish("tool_use");
    let (p, _) = provider("https://example.test", 200, body);
    let (events, result) = collect(&p, input());
    result.unwrap();
    assert_eq!(
        events,
        vec![
            InferenceEvent::ContentDelta {
                text: "héj".into()
            },
            InferenceEvent::ToolCall {
                call: InferenceToolCall {
                    id: "c".into(),
                    kind: "function".into(),
                    name: "search".into(),
                    arguments: "{\"q\":1}".into()
                }
            },
            InferenceEvent::Finished {
                reason: InferenceFinishReason::ToolCalls
            }
        ]
    );
}

#[test]
fn requires_termination_reason_and_completed_tools_even_for_text_only() {
    for body in [
        String::new(),
        sse(&[json!({"type":"message_stop"})]),
        sse(&[json!({"type":"message_delta","delta":{"stop_reason":"end_turn"}})]),
        sse(&[
            json!({"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"c","name":"search"}}),
        ]) + &finish("tool_use"),
    ] {
        let (p, _) = provider("https://example.test", 200, body);
        let mut input = input();
        input.text_only = true;
        assert!(matches!(
            collect(&p, input).1,
            Err(InferenceError::Interrupted)
        ));
    }
    for reason in ["max_tokens", "refusal", "future"] {
        let (p, _) = provider("https://example.test", 200, finish(reason));
        let error = collect(&p, input()).1.unwrap_err();
        assert!(if reason == "max_tokens" {
            matches!(error, InferenceError::OutputLimit)
        } else {
            matches!(error, InferenceError::PolicyStop)
        });
    }
}

#[test]
fn malformed_unknown_events_and_api_errors_preserve_semantics() {
    let (p, _) = provider(
        "https://example.test",
        200,
        format!(
            "event: content_block_delta\ndata: broken\nevent: content_block_delta\ndata: {{\"index\":0,\"delta\":{{\"type\":\"text_delta\",\"text\":5}}}}\nevent: future\ndata: {{}}\n{}",
            finish("end_turn")
        ),
    );
    assert_eq!(
        collect(&p, input()).0,
        vec![InferenceEvent::Finished {
            reason: InferenceFinishReason::Stop
        }]
    );
    let (p, _) = provider(
        "https://example.test",
        200,
        sse(&[json!({"type":"error","error":{"type":"overloaded_error","message":"busy"}})]),
    );
    assert!(
        matches!(collect(&p,input()).1,Err(InferenceError::Http{status:500,body:Some(body)}) if body == "overloaded_error: busy")
    );
    let (p, _) = provider("https://example.test", 429, "limited");
    assert!(
        matches!(collect(&p,input()).1,Err(InferenceError::Http{status:429,body:Some(body)}) if body == "limited")
    );
}

mod diagnostics;
mod streams;
