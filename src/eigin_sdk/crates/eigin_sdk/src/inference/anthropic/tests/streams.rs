use super::*;

#[test]
fn interleaved_tool_blocks_keep_arguments_and_complete_in_stop_order() {
    let body = sse(&[
        json!({"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"weather-call","name":"weather"}}),
        json!({"type":"content_block_start","index":3,"content_block":{"type":"tool_use","id":"search-call","name":"search"}}),
        json!({"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\"city\":"}}),
        json!({"type":"content_block_delta","index":3,"delta":{"type":"input_json_delta","partial_json":"{\"query\":"}}),
        json!({"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"\"Oslo\"}"}}),
        json!({"type":"content_block_delta","index":3,"delta":{"type":"input_json_delta","partial_json":"\"rain\"}"}}),
        json!({"type":"content_block_stop","index":3}),
        json!({"type":"content_block_stop","index":1}),
    ]) + &finish("tool_use");
    let (provider, _) = provider("https://example.test", 200, body);
    let (events, result) = collect(&provider, input());
    result.unwrap();
    assert_eq!(
        events,
        vec![
            InferenceEvent::ToolCall {
                call: InferenceToolCall {
                    id: "search-call".into(),
                    kind: "function".into(),
                    name: "search".into(),
                    arguments: "{\"query\":\"rain\"}".into(),
                }
            },
            InferenceEvent::ToolCall {
                call: InferenceToolCall {
                    id: "weather-call".into(),
                    kind: "function".into(),
                    name: "weather".into(),
                    arguments: "{\"city\":\"Oslo\"}".into(),
                }
            },
            InferenceEvent::Finished {
                reason: InferenceFinishReason::ToolCalls
            },
        ]
    );
}
