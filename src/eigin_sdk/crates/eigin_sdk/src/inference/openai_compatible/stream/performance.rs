use super::StreamParser;
use serde_json::Value;

impl StreamParser {
    pub(super) fn observe_performance(&mut self, payload: &[u8]) {
        let Ok(json) = serde_json::from_slice::<Value>(payload) else {
            return;
        };
        if let Some(choices) = json.get("choices").and_then(Value::as_array) {
            for choice in choices {
                let Some(delta) = choice.get("delta") else {
                    continue;
                };
                let text = super::wire::project_content(delta.get("content"))
                    .ok()
                    .flatten()
                    .is_some_and(|text| !text.is_empty());
                let tool = delta
                    .get("tool_calls")
                    .and_then(Value::as_array)
                    .is_some_and(|calls| {
                        calls.iter().any(|call| {
                            call.get("function").is_some_and(|function| {
                                ["name", "arguments"].iter().any(|key| {
                                    function
                                        .get(key)
                                        .and_then(Value::as_str)
                                        .is_some_and(|value| !value.is_empty())
                                })
                            })
                        })
                    });
                if text || tool {
                    self.performance.useful_output();
                }
            }
        }
        if let Some(usage) = json.get("usage") {
            self.performance.tokens(
                usage.get("completion_tokens").and_then(Value::as_u64),
                usage
                    .pointer("/completion_tokens_details/reasoning_tokens")
                    .and_then(Value::as_u64),
            );
        }
    }
}
