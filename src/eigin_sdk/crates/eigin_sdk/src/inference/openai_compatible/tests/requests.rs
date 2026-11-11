use super::*;

#[test]
fn models_are_sorted_deduplicated_and_headers_and_paths_preserved() {
    let _registration = crate::diagnostics::delivery::tests::RECEIVER_TEST_LOCK
        .lock()
        .unwrap();
    let (provider, transport) = provider(
        "https://example.test/v1/",
        200,
        r#"{"data":[{"id":"z"},{"id":"a"},{"id":"z"}]}"#,
    );
    assert_eq!(
        block_on(provider.discovery().fetch_models()).unwrap(),
        ["a", "z"]
    );
    let requests = transport.requests.lock().unwrap();
    assert_eq!(requests[0].url, "https://example.test/v1/models");
    assert_eq!(requests[0].headers["authorization"], "Bearer test-key");
    assert_eq!(requests[0].headers["x-example"], "extra");
}

#[test]
fn discovery_errors_and_minimal_validation_request() {
    let _registration = crate::diagnostics::delivery::tests::RECEIVER_TEST_LOCK
        .lock()
        .unwrap();
    let (bad, _) = provider("ht tp://inva lid", 200, "");
    assert!(matches!(
        block_on(bad.discovery().fetch_models()),
        Err(InferenceError::InvalidUrl { .. })
    ));
    let (unauthorized, _) = provider("https://example.test/v1", 401, "");
    assert!(matches!(
        block_on(unauthorized.discovery().fetch_models()),
        Err(InferenceError::Http { status: 401, .. })
    ));
    for status in [200, 400, 401, 403, 404, 429, 500] {
        let (provider, transport) = provider("https://example.test/v1", status, "{}");
        let result = block_on(
            provider
                .key_validation()
                .validate_api_key("some-model".into()),
        );
        assert_eq!(result.is_err(), status == 401 || status == 403);
        assert_eq!(
            request_body(&transport),
            json!({"model":"some-model","messages":[{"role":"user","content":"hi"}],"stream":false,"max_tokens":1})
        );
    }
}

#[test]
fn cache_reasoning_and_schema_fields_follow_adapter_policy() {
    for (base, family, cache, ephemeral) in [
        ("https://example.test/v1", None, true, false),
        (
            "https://example.test/v1",
            Some(InferenceModelFamily::Anthropic),
            true,
            false,
        ),
        (
            "https://openrouter.ai/api/v1",
            Some(InferenceModelFamily::Other),
            true,
            false,
        ),
        (
            "https://generativelanguage.googleapis.com/v1beta/openai",
            None,
            false,
            false,
        ),
        (
            "https://router.test/v1",
            Some(InferenceModelFamily::Google),
            false,
            false,
        ),
        (
            "https://openrouter.ai/api/v1",
            Some(InferenceModelFamily::Anthropic),
            false,
            true,
        ),
    ] {
        for effort in [None, Some("low"), Some("high"), Some("none")] {
            let (provider, transport) = provider(base, 200, finished());
            let mut input = input();
            input.model_family = family;
            input.prompt_cache_key = Some("chat-123".into());
            input.reasoning_effort = effort.map(str::to_owned);
            input.tools = Some(vec![InferenceToolDefinition {
                name: "lookup".into(),
                description: "Find it".into(),
                parameters_json: r#"{"type":"object","properties":{}}"#.into(),
            }]);
            collect(&provider, input).1.unwrap();
            let body = request_body(&transport);
            assert_eq!(body.get("prompt_cache_key").is_some(), cache);
            assert_eq!(body.get("cache_control").is_some(), ephemeral);
            assert_eq!(body["reasoning_effort"].as_str(), effort);
            assert_eq!(
                body["tools"][0]["function"]["parameters"]["properties"],
                json!({})
            );
        }
    }
}

#[test]
fn images_and_unavailable_attachment_bytes_preserve_wire_content() {
    let cases = [
        (Some("hello"), false, false, json!("hello")),
        (
            Some("hello"),
            true,
            true,
            json!([{"type":"text","text":"hello"},{"type":"image_url","image_url":{"url":"data:image/jpeg;base64,AQID","detail":"high"}}]),
        ),
        (
            None,
            true,
            true,
            json!([{"type":"image_url","image_url":{"url":"data:image/jpeg;base64,AQID","detail":"high"}}]),
        ),
        (
            Some("hello"),
            true,
            false,
            json!([{"type":"text","text":"hello"}]),
        ),
        (None, true, false, Value::Null),
    ];
    for (text, has_attachments, image, expected) in cases {
        let (provider, transport) = provider("https://example.test/v1", 200, finished());
        let mut input = input();
        input.messages = vec![InferenceMessage {
            role: "user".into(),
            content: text.map(str::to_owned),
            has_attachments,
            images: if image {
                vec![InferenceImage {
                    mime_type: "image/jpeg".into(),
                    bytes: vec![1, 2, 3],
                }]
            } else {
                vec![]
            },
            ..Default::default()
        }];
        collect(&provider, input).1.unwrap();
        let body = request_body(&transport);
        assert_eq!(body["messages"][0]["content"], expected);
        if expected.is_null() {
            assert!(body["messages"][0].get("content").is_none());
        }
    }
}

#[test]
fn tool_ids_and_gemini_signatures_are_replayed() {
    for (base, expected_id, signature) in [
        ("https://api.mistral.ai/v1", "123456789", false),
        (
            "https://generativelanguage.googleapis.com/v1beta/openai",
            "call_123456789",
            true,
        ),
    ] {
        let (provider, transport) = provider(base, 200, finished());
        let mut input = input();
        input.messages = vec![
            InferenceMessage {
                role: "assistant".into(),
                tool_calls: Some(vec![InferenceToolCall {
                    id: "call_123456789".into(),
                    kind: "function".into(),
                    name: "lookup".into(),
                    arguments: "{}".into(),
                }]),
                provider_metadata: [("thought_signature".into(), "opaque".into())].into(),
                ..Default::default()
            },
            InferenceMessage {
                role: "tool".into(),
                tool_call_id: Some("call_123456789".into()),
                ..Default::default()
            },
        ];
        collect(&provider, input).1.unwrap();
        let body = request_body(&transport);
        assert_eq!(body["messages"][0]["tool_calls"][0]["id"], expected_id);
        assert_eq!(body["messages"][1]["tool_call_id"], expected_id);
        assert_eq!(
            body["messages"][0]["tool_calls"][0]
                .get("extra_content")
                .is_some(),
            signature
        );
    }
}

#[test]
fn model_not_found_requires_status_and_model_hint() {
    for body in [
        "model_not_found",
        "model not found",
        "no such model",
        "unknown model",
        "invalid model ID",
        "unsupported model",
        "The model x does not exist",
        "model is not available",
        "not a valid model",
    ] {
        for status in [400, 404] {
            assert!(
                inference_model_not_found(status, Some(body.into())),
                "{body}"
            );
        }
        for status in [401, 500] {
            assert!(!inference_model_not_found(status, Some(body.into())));
        }
    }
    for body in [
        "Not Found",
        "Resource not found",
        "credit balance",
        "missing field",
        "",
    ] {
        assert!(!inference_model_not_found(404, Some(body.into())));
    }
    assert!(!inference_model_not_found(404, None));
}

#[test]
fn empty_tokens_omit_bearer_authentication_and_preserve_explicit_headers() {
    let _registration = crate::diagnostics::delivery::tests::RECEIVER_TEST_LOCK
        .lock()
        .unwrap();
    for authorization in [None, Some("Basic host-supplied")] {
        let (_, transport) = provider("https://example.test/v1", 200, r#"{"data":[]}"#);
        let client = crate::inference::OpenAiCompatibleProvider::with_transport(
            InferenceProviderConfig {
                base_url: "https://example.test/v1".into(),
                api_token: String::new(),
                extra_headers: authorization
                    .map(|value| ("Authorization".into(), value.into()))
                    .into_iter()
                    .collect(),
            },
            Box::new(transport.clone()),
        );
        block_on(client.discovery().fetch_models()).unwrap();
        let requests = transport.requests.lock().unwrap();
        assert_eq!(
            requests[0].headers.get("authorization").map(String::as_str),
            authorization
        );
    }
}
