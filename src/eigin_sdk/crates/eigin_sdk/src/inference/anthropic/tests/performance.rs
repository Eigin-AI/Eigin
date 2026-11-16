use super::*;

#[test]
fn performance_tracks_text_and_tools_using_final_thinking_token_accounting() {
    for tool in [false, true] {
        for reasoning_tokens in [Some(100), None, Some(109)] {
            let mut events = vec![
                json!({"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"private"}}),
            ];
            if tool {
                events.extend([
                    json!({"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"call","name":"lookup"}}),
                    json!({"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{}"}}),
                    json!({"type":"content_block_stop","index":1}),
                ]);
            } else {
                events.extend([
                    json!({"type":"content_block_start","index":1,"content_block":{"type":"text","text":"hello"}}),
                    json!({"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":" world"}}),
                ]);
            }
            events.extend([
                json!({"type":"message_delta","delta":{"stop_reason":if tool {"tool_use"} else {"end_turn"}},"usage":{"output_tokens":108,"output_tokens_details":{"thinking_tokens":reasoning_tokens}}}),
                json!({"type":"message_stop"}),
            ]);
            let (provider, _) = provider("https://example.test", 200, sse(&events));
            let (events, result) = collect_all(&provider, input());
            result.unwrap();
            let measurements: Vec<_> = events
                .iter()
                .filter_map(|event| match event {
                    InferenceEvent::Performance { measurement } => Some(measurement),
                    _ => None,
                })
                .collect();
            assert_eq!(measurements.len(), 1);
            assert!(measurements[0].time_to_first_token_ms.unwrap() > 0.0);
            assert_eq!(
                measurements[0].tokens_per_second.is_some(),
                reasoning_tokens == Some(100)
            );
            assert!(matches!(
                events.last(),
                Some(InferenceEvent::Finished { .. })
            ));
        }
    }
}

#[test]
fn thinking_only_streams_have_no_useful_output_measurements() {
    let body = sse(&[
        json!({"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"private"}}),
    ]) + &finish("end_turn");
    let (provider, _) = provider("https://example.test", 200, body);
    let (events, result) = collect_all(&provider, input());
    result.unwrap();
    assert!(events.iter().any(|event| matches!(event, InferenceEvent::Performance { measurement } if measurement.time_to_first_token_ms.is_none() && measurement.tokens_per_second.is_none())));
}
