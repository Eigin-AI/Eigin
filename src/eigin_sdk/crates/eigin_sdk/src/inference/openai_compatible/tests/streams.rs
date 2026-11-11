use super::*;

#[test]
fn interrupted_streams_never_emit_partial_tool_calls() {
    for ending in ["", "data: [DONE]\n\n"] {
        let body = sse(&[chunk(
            json!({"tool_calls":[{"index":0,"id":"call_1","function":{"name":"lookup","arguments":"{"}}]}),
            None,
        )]) + ending;
        let (provider, _) = provider("https://example.test/v1", 200, body);
        let (events, result) = collect(&provider, input());
        assert!(events.is_empty());
        assert!(matches!(result, Err(InferenceError::Interrupted)));
    }
}

#[test]
fn finish_limits_refusals_and_inline_errors_preserve_partial_text() {
    for (delta, reason, kind) in [
        (json!({"content":"partial"}), "length", "limit"),
        (json!({}), "content_filter", "policy"),
        (json!({"refusal":"I cannot help."}), "stop", "policy"),
        (json!({}), "unknown", "policy"),
    ] {
        let (provider, _) = provider(
            "https://example.test/v1",
            200,
            sse(&[chunk(delta.clone(), Some(reason))]),
        );
        let (events, result) = collect(&provider, input());
        if kind == "limit" {
            assert!(matches!(result, Err(InferenceError::OutputLimit)));
        } else {
            assert!(matches!(result, Err(InferenceError::PolicyStop)));
        }
        if delta.get("refusal").is_some() {
            assert_eq!(
                events[0],
                InferenceEvent::ContentDelta {
                    text: "I cannot help.".into()
                }
            );
        }
    }
    let (provider, _) = provider(
        "https://example.test/v1",
        200,
        sse(&[json!({"error":{"type":"quota","message":"exhausted"}})]),
    );
    assert!(
        matches!(collect(&provider,input()).1, Err(InferenceError::Http { status:0, body:Some(body) }) if body == "exhausted")
    );
}

#[test]
fn interleaved_and_indexless_tools_are_assembled_and_sorted() {
    for indexless in [false, true] {
        let mut first = json!({"index":0,"id":"call_1","type":"function","function":{"name":"read_core","arguments":"{\"cor"}});
        let mut second = json!({"index":1,"id":"call_2","function":{"name":"set_presentation","arguments":"{\"emoji\":"},"extra_content":{"google":{"thought_signature":"opaque"}}});
        let mut first_tail = json!({"index":0,"function":{"arguments":"e\":\"identity\"}"}});
        let mut second_tail = json!({"index":1,"function":{"arguments":"\"🧠\"}"}});
        if indexless {
            for delta in [&mut first, &mut second, &mut first_tail, &mut second_tail] {
                delta.as_object_mut().unwrap().remove("index");
            }
            first_tail["id"] = json!("call_1");
            second_tail["id"] = json!("call_2");
        }
        let body = sse(&[
            chunk(json!({"tool_calls":[first,second]}), None),
            chunk(
                json!({"tool_calls":[second_tail,first_tail]}),
                Some(if indexless { "stop" } else { "tool_calls" }),
            ),
        ]);
        let (provider, _) = provider(
            "https://generativelanguage.googleapis.com/v1beta/openai",
            200,
            body,
        );
        let (events, result) = collect(&provider, input());
        result.unwrap();
        assert!(
            matches!(&events[0], InferenceEvent::ProviderMetadata { values } if values["thought_signature"] == "opaque")
        );
        assert!(
            matches!(&events[1], InferenceEvent::ToolCall { call } if call.id == "call_1" && call.arguments == r#"{"core":"identity"}"#)
        );
        assert!(
            matches!(&events[2], InferenceEvent::ToolCall { call } if call.id == "call_2" && call.arguments == r#"{"emoji":"🧠"}"#)
        );
        assert_eq!(
            events[3],
            InferenceEvent::Finished {
                reason: InferenceFinishReason::ToolCalls
            }
        );
    }
}

#[test]
fn plain_text_mode_preserves_legacy_eof_and_structured_projection() {
    let body = sse(&[
        chunk(
            json!({"content":[{"type":"thinking","thinking":[{"type":"text","text":"private"}]},{"type":"text","text":"H"},{"type":"text","text":"e"}]}),
            None,
        ),
        chunk(json!({"content":"j æøå!"}), None),
    ]);
    let (provider, _) = provider("https://api.mistral.ai/v1", 200, body);
    let mut input = input();
    input.text_only = true;
    let (events, result) = collect(&provider, input);
    result.unwrap();
    assert_eq!(
        events,
        vec![
            InferenceEvent::ContentDelta { text: "He".into() },
            InferenceEvent::ContentDelta {
                text: "j æøå!".into()
            }
        ]
    );
}

#[test]
fn sse_crlf_comments_optional_space_and_malformed_chunks() {
    let body = format!(
        ": comment\r\ndata: not-json\r\ndata:{}\r\rdata: [DONE]\r",
        chunk(json!({"content":"hello 👋"}), Some("stop"))
    );
    let (provider, _) = provider("https://example.test/v1", 200, body);
    let (events, result) = collect(&provider, input());
    result.unwrap();
    assert_eq!(
        events[0],
        InferenceEvent::ContentDelta {
            text: "hello 👋".into()
        }
    );
}

#[test]
fn http_failure_arrives_at_open_and_cancel_before_open_sends_nothing() {
    let _registration = crate::diagnostics::delivery::tests::RECEIVER_TEST_LOCK
        .lock()
        .unwrap();
    let (provider, transport) = provider("https://example.test/v1", 429, "quota");
    let completion = provider.stream(input()).unwrap();
    assert!(
        matches!(block_on(completion.open()), Err(InferenceError::Http { status:429, body:Some(body) }) if body == "quota")
    );
    let cancelled = provider.stream(input()).unwrap();
    cancelled.cancel();
    cancelled.cancel();
    assert!(matches!(
        block_on(cancelled.next()),
        Err(InferenceError::Cancelled)
    ));
    assert_eq!(transport.requests.lock().unwrap().len(), 1);
}

#[test]
fn oversized_sse_lines_fail_independently_of_transport_chunk_boundaries() {
    for size in [32 * 1024, 64 * 1024, 1024 * 1024] {
        for ending in ["\n\n", ""] {
            let body = format!(
                "data: {}{ending}",
                chunk(json!({"content":"x".repeat(1024*1024)}), Some("stop"))
            );
            let (provider, transport) = provider("https://example.test/v1", 200, body);
            transport.chunk_size.store(size, Ordering::Relaxed);
            let (events, result) = collect(&provider, input());
            assert!(events.is_empty());
            assert!(matches!(result, Err(InferenceError::LimitExceeded { .. })));
        }
    }
}

#[test]
fn standard_stop_does_not_emit_pending_tools_and_operations_do_not_share_state() {
    let body = sse(&[chunk(
        json!({"tool_calls":[{"index":0,"id":"call_1","function":{"name":"lookup","arguments":"{}"}}]}),
        Some("stop"),
    )]);
    let (provider, _) = provider("https://openrouter.ai/api/v1", 200, body);
    for _ in 0..2 {
        let mut input = input();
        input.model_family = Some(InferenceModelFamily::Anthropic);
        let (events, result) = collect(&provider, input);
        result.unwrap();
        assert_eq!(
            events,
            vec![InferenceEvent::Finished {
                reason: InferenceFinishReason::Stop
            }]
        );
    }
}

#[test]
fn http_failures_remain_failed_across_open_and_next() {
    let _registration = crate::diagnostics::delivery::tests::RECEIVER_TEST_LOCK
        .lock()
        .unwrap();
    for open_first in [true, false] {
        let (provider, _) = provider("https://example.com/v1", 429, "slow down");
        let stream = provider.stream(input()).unwrap();
        block_on(async {
            let error = if open_first {
                stream.open().await.unwrap_err()
            } else {
                stream.next().await.unwrap_err()
            };
            assert!(matches!(error, InferenceError::Http { status: 429, .. }));
            assert_eq!(stream.next().await.unwrap(), None);
            assert!(matches!(
                stream.open().await,
                Err(InferenceError::Http { status: 429, .. })
            ));
        });
    }
}
