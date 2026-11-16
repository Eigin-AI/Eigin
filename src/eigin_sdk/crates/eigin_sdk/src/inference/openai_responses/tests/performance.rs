use super::*;

#[test]
fn performance_tracks_text_and_tool_deltas_with_completed_response_usage() {
    for tool in [false, true] {
        for reasoning_tokens in [Some(100), None, Some(109)] {
            let mut events =
                vec![json!({"type":"response.reasoning_text.delta","delta":"private"})];
            if tool {
                events.extend([
                    json!({"type":"response.output_item.added","item":{"type":"function_call","id":"item","call_id":"call","name":"lookup"}}),
                    json!({"type":"response.function_call_arguments.delta","item_id":"item","delta":"{}"}),
                    json!({"type":"response.output_item.done","item":{"type":"function_call","id":"item","call_id":"call","name":"lookup","arguments":"{}"}}),
                ]);
            } else {
                events.extend([
                    json!({"type":"response.output_text.delta","delta":"hello"}),
                    json!({"type":"response.output_text.delta","delta":" world"}),
                ]);
            }
            events.push(json!({"type":"response.completed","response":{"usage":{"output_tokens":108,"output_tokens_details":{"reasoning_tokens":reasoning_tokens}}}}));
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
fn reasoning_only_streams_have_no_useful_output_measurements() {
    let (provider, _) = provider(
        "https://example.test",
        200,
        sse(&[
            json!({"type":"response.reasoning_text.delta","delta":"private"}),
            completed(),
        ]),
    );
    let (events, result) = collect_all(&provider, input());
    result.unwrap();
    assert!(events.iter().any(|event| matches!(event, InferenceEvent::Performance { measurement } if measurement.time_to_first_token_ms.is_none() && measurement.tokens_per_second.is_none())));
}
