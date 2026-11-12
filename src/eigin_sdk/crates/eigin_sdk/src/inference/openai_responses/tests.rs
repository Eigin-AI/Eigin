use super::super::types::*;
use futures::executor::block_on;
use serde_json::json;
mod support;
use support::*;

fn completed() -> serde_json::Value {
    json!({"type":"response.completed"})
}
fn message(role: &str, content: &str) -> InferenceMessage {
    InferenceMessage {
        role: role.into(),
        content: Some(content.into()),
        ..Default::default()
    }
}

#[test]
fn requests_preserve_instructions_tools_images_and_omissions() {
    let (provider, transport) = provider("https://example.test/v1", 200, sse(&[completed()]));
    let mut input = input();
    input.reasoning_effort = Some("high".into());
    input.prompt_cache_key = Some("ignored".into());
    input.messages = vec![
        message("system", "one"),
        message("developer", "two"),
        InferenceMessage {
            images: vec![InferenceImage {
                mime_type: "image/png".into(),
                bytes: vec![1, 2, 3],
            }],
            ..message("user", "hello")
        },
        InferenceMessage {
            tool_calls: Some(vec![InferenceToolCall {
                id: "call1".into(),
                kind: "function".into(),
                name: "search".into(),
                arguments: "{}".into(),
            }]),
            ..message("assistant", "looking")
        },
        InferenceMessage {
            tool_call_id: Some("call1".into()),
            ..message("tool", "result")
        },
    ];
    input.tools = Some(vec![InferenceToolDefinition {
        name: "search".into(),
        description: "Search".into(),
        parameters_json: "{\"type\":\"object\"}".into(),
    }]);
    assert!(collect(&provider, input).1.is_ok());
    let body = request_body(&transport);
    assert_eq!(body["instructions"], "one\n\ntwo");
    assert_eq!(body["store"], false);
    assert_eq!(body["stream"], true);
    assert_eq!(
        body["input"][0]["content"][1],
        json!({"type":"input_image","image_url":"data:image/png;base64,AQID"})
    );
    assert_eq!(
        body["input"][1]["content"][0],
        json!({"type":"output_text","text":"looking"})
    );
    assert_eq!(
        body["input"][2],
        json!({"type":"function_call","call_id":"call1","name":"search","arguments":"{}"})
    );
    assert_eq!(
        body["input"][3],
        json!({"type":"function_call_output","call_id":"call1","output":"result"})
    );
    assert_eq!(body["tools"][0]["name"], "search");
    assert!(body["tools"][0].get("function").is_none());
    for field in [
        "temperature",
        "top_p",
        "max_output_tokens",
        "previous_response_id",
        "reasoning",
        "prompt_cache_key",
    ] {
        assert!(body.get(field).is_none(), "{field}");
    }
    let requests = transport.requests.lock().unwrap();
    assert_eq!(requests[0].url, "https://example.test/v1/responses");
    assert_eq!(
        requests[0].headers.get("authorization").map(String::as_str),
        Some("Bearer test-key")
    );
}

#[test]
fn empty_and_unloaded_content_preserves_fallback() {
    let (provider, transport) = provider("https://example.test", 200, sse(&[completed()]));
    let mut input = input();
    input.messages = vec![
        InferenceMessage {
            has_attachments: true,
            ..message("user", "")
        },
        message("tool", "orphan"),
        message("assistant", ""),
    ];
    assert!(collect(&provider, input).1.is_ok());
    assert_eq!(
        request_body(&transport)["input"],
        json!([{"type":"message","role":"user","content":[{"type":"input_text","text":""}]}])
    );
}

#[test]
fn discovery_preserves_order_visibility_and_both_shapes() {
    let _lock = crate::diagnostics::delivery::tests::RECEIVER_TEST_LOCK
        .lock()
        .unwrap();
    for body in [
        json!({"models":[{"slug":"z","visibility":"list"},{"id":"a"},{"slug":"hidden","visibility":"internal"},{"slug":"z"}]}),
        json!({"data":[{"id":"z"},{"id":"a"},{"id":"z"}]}),
    ] {
        let (provider, _) = provider("https://example.test", 200, body.to_string());
        assert_eq!(
            block_on(provider.discovery().fetch_models()).unwrap(),
            vec!["z", "a"]
        );
    }
}

#[test]
fn validation_rejects_only_auth_statuses() {
    let _lock = crate::diagnostics::delivery::tests::RECEIVER_TEST_LOCK
        .lock()
        .unwrap();
    for status in [200, 400, 401, 403, 404, 429, 500] {
        let (provider, transport) = provider("https://example.test", status, "{}");
        let result = block_on(provider.key_validation().validate_api_key("model".into()));
        if status == 401 || status == 403 {
            assert!(matches!(
                result,
                Err(InferenceError::SubscriptionInvalidUser)
            ));
        } else {
            result.unwrap();
        }
        assert_eq!(
            request_body(&transport)["input"][0]["content"][0]["text"],
            "hi"
        );
    }
}

#[test]
fn fragmented_stream_delivers_text_tools_and_finish() {
    let (provider, _) = provider(
        "https://example.test",
        200,
        sse(&[
            json!({"type":"response.output_text.delta","delta":"héj"}),
            json!({"type":"response.output_item.done","item":{"type":"function_call","call_id":"c","name":"search","arguments":"{}"}}),
            completed(),
        ]),
    );
    let (events, result) = collect(&provider, input());
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
                    arguments: "{}".into()
                }
            },
            InferenceEvent::Finished {
                reason: InferenceFinishReason::ToolCalls
            }
        ]
    );
}

#[test]
fn refusal_incomplete_and_missing_completion_fail() {
    for (event, policy) in [
        (json!({"type":"response.refusal.done"}), true),
        (
            json!({"type":"response.incomplete","response":{"incomplete_details":{"reason":"content_filter"}}}),
            true,
        ),
        (
            json!({"type":"response.incomplete","response":{"incomplete_details":{"reason":"max_output_tokens"}}}),
            false,
        ),
    ] {
        let (provider, _) = provider("https://example.test", 200, sse(&[event]));
        let error = collect(&provider, input()).1.unwrap_err();
        assert!(if policy {
            matches!(error, InferenceError::PolicyStop)
        } else {
            matches!(error, InferenceError::OutputLimit)
        });
    }
    for body in [
        "",
        "data: [DONE]\n",
        "data: {\"type\":\"response.output_text.delta\",\"delta\":\"partial\"}\n",
    ] {
        let (provider, _) = provider("https://example.test", 200, body);
        assert!(matches!(
            collect(&provider, input()).1,
            Err(InferenceError::Interrupted)
        ));
    }
    let (provider, _) = provider(
        "https://example.test",
        200,
        sse(&[
            json!({"type":"response.refusal.delta","delta":"no"}),
            completed(),
        ]),
    );
    let (events, result) = collect(&provider, input());
    assert_eq!(
        events,
        vec![InferenceEvent::ContentDelta { text: "no".into() }]
    );
    assert!(matches!(result, Err(InferenceError::PolicyStop)));
}

#[test]
fn subscription_errors_survive_http_and_stream_envelopes() {
    for (suffix, expected) in [
        ("user_not_eligible", "SubscriptionPlanNotEligible"),
        ("usage_limit_exceeded", "SubscriptionUsageLimitExceeded"),
        ("invalid_user", "SubscriptionInvalidUser"),
        ("usage_unavailable", "SubscriptionUsageUnavailable"),
        ("user_unavailable", "SubscriptionUsageUnavailable"),
        (
            "unsupported_capability",
            "SubscriptionUnsupportedCapability",
        ),
    ] {
        let error = json!({"code":format!("subscription_sharing_{suffix}"),"param":"tools"});
        for (status, body) in [
            (400, error.to_string()),
            (
                200,
                sse(&[json!({"type":"response.failed","response":{"error":error}})]),
            ),
            (
                200,
                sse(&[json!({"type":"error","code":error["code"],"message":"tools"})]),
            ),
        ] {
            let (provider, _) = provider("https://example.test", status, body);
            assert!(
                format!("{:?}", collect(&provider, input()).1.unwrap_err()).starts_with(expected)
            );
        }
    }
}

#[test]
fn malformed_unknown_events_are_skipped_and_text_only_still_requires_completion() {
    let (provider, _) = provider(
        "https://example.test",
        200,
        format!(
            "event: ignored\ndata: broken\ndata: {{\"type\":\"future.event\"}}\n{}",
            sse(&[completed()])
        ),
    );
    assert_eq!(
        collect(&provider, input()).0,
        vec![InferenceEvent::Finished {
            reason: InferenceFinishReason::Stop
        }]
    );
    let (provider, _) = support::provider("https://example.test", 200, "data: [DONE]\n");
    let mut input = input();
    input.text_only = true;
    assert!(matches!(
        collect(&provider, input).1,
        Err(InferenceError::Interrupted)
    ));
}

mod cancellation;

#[test]
fn malformed_typed_fields_are_skipped_and_refusal_overrides_later_errors() {
    let (provider, _) = provider(
        "https://example.test",
        200,
        sse(&[
            json!({"type":"response.output_item.done","item":{"type":"function_call","arguments":{}}}),
            json!({"type":"response.completed","response":[]}),
            json!({"type":"response.output_text.delta","delta":"after malformed completion"}),
            completed(),
        ]),
    );
    let (events, result) = collect(&provider, input());
    result.unwrap();
    assert_eq!(
        events,
        vec![
            InferenceEvent::ContentDelta {
                text: "after malformed completion".into()
            },
            InferenceEvent::Finished {
                reason: InferenceFinishReason::Stop
            }
        ]
    );
    for event in [
        json!({"type":"response.incomplete"}),
        json!({"type":"response.failed"}),
        json!({"type":"error","code":"subscription_sharing_usage_unavailable"}),
    ] {
        let (provider, _) = support::provider(
            "https://example.test",
            200,
            sse(&[json!({"type":"response.refusal.delta","delta":"no"}), event]),
        );
        assert!(matches!(
            collect(&provider, input()).1,
            Err(InferenceError::PolicyStop)
        ));
    }
}

#[test]
fn discovery_errors_and_missing_tool_ids_preserve_supported_behavior() {
    {
        let _lock = crate::diagnostics::delivery::tests::RECEIVER_TEST_LOCK
            .lock()
            .unwrap();
        let (provider, _) = provider(
            "https://example.test",
            403,
            "{\"detail\":{\"code\":\"subscription_sharing_user_not_eligible\"}}",
        );
        assert!(matches!(
            block_on(provider.discovery().fetch_models()),
            Err(InferenceError::SubscriptionPlanNotEligible)
        ));
    }
    let (provider, _) = provider(
        "https://example.test",
        200,
        sse(&[
            json!({"type":"response.output_item.done","item":{"type":"function_call"}}),
            json!({"type":"response.output_item.done","item":{"type":"function_call"}}),
            completed(),
        ]),
    );
    let (events, result) = collect(&provider, input());
    result.unwrap();
    let ids = events
        .iter()
        .filter_map(|event| {
            if let InferenceEvent::ToolCall { call } = event {
                Some(&call.id)
            } else {
                None
            }
        })
        .collect::<Vec<_>>();
    assert_eq!(ids.len(), 2);
    assert_ne!(ids[0], ids[1]);
    for id in ids {
        assert_eq!(uuid::Uuid::parse_str(id).unwrap().get_version_num(), 4);
    }
}
