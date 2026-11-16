//! Stream measurements without retaining response content after each event.

use serde_json::Value;
use std::time::Duration;

use super::{Observation, Outcome, Source};

const MAX_EVENT_BYTES: usize = 1024 * 1024;

/// Measures useful output. Reasoning and transport events do not stop TTFT.
#[derive(Default)]
pub struct StreamMeasurement {
    pending: Vec<u8>,
    first: Option<Duration>,
    last: Option<Duration>,
    useful_tokens: Option<u64>,
    reasoning_seen: bool,
    backpressured: bool,
    first_output_backpressured: bool,
    failed: bool,
    complete: bool,
    invalid: bool,
}

impl StreamMeasurement {
    /// Observe upstream bytes before downstream delivery. Elapsed starts at dispatch.
    pub fn observe(&mut self, bytes: &[u8], elapsed: Duration) {
        if self.invalid {
            return;
        }
        for &byte in bytes {
            if byte == b'\n' {
                let line = std::mem::take(&mut self.pending);
                self.line(&line, elapsed);
            } else {
                self.pending.push(byte);
                if self.pending.len() > MAX_EVENT_BYTES {
                    self.pending.clear();
                    self.invalid = true;
                    return;
                }
            }
        }
    }

    /// Omit throughput if downstream delivery stalled upstream reads.
    pub fn mark_backpressure(&mut self) {
        self.backpressured = true;
        self.first_output_backpressured |= self.first.is_none();
    }

    /// Mark a stream transport failure independently of response content.
    pub fn mark_failure(&mut self) {
        self.failed = true;
    }

    /// Build one terminal observation. Callers discard cancelled requests entirely.
    pub fn finish(
        mut self,
        model_id: String,
        source: Source,
        observed_at_ms: i64,
        elapsed: Duration,
    ) -> Observation {
        let trailing = std::mem::take(&mut self.pending);
        if !trailing.is_empty() {
            self.line(&trailing, elapsed);
        }
        let success = !self.failed && !self.invalid && self.complete;
        let tps = if success && !self.backpressured {
            self.first
                .zip(self.last)
                .zip(self.useful_tokens)
                .and_then(|((first, last), tokens)| {
                    let seconds = last.saturating_sub(first).as_secs_f64();
                    (tokens >= 4 && seconds > 0.0).then_some(tokens as f64 / seconds)
                })
        } else {
            None
        };
        Observation {
            model_id,
            source,
            observed_at_ms,
            outcome: if success {
                Outcome::Success
            } else {
                Outcome::UpstreamFailure
            },
            ttft_ms: self
                .first
                .filter(|_| !self.first_output_backpressured)
                .map(|duration| duration.as_secs_f64() * 1000.0),
            tps,
        }
    }

    fn line(&mut self, line: &[u8], elapsed: Duration) {
        let Ok(line) = std::str::from_utf8(line) else {
            return;
        };
        let Some(data) = line.trim_end().strip_prefix("data:") else {
            return;
        };
        if data.trim() == "[DONE]" {
            self.complete = true;
            return;
        }
        let Ok(json) = serde_json::from_str::<Value>(data) else {
            return;
        };
        if json.get("error").is_some_and(|error| !error.is_null()) {
            self.failed = true;
        }
        if let Some(choices) = json.get("choices").and_then(Value::as_array) {
            for choice in choices {
                let Some(delta) = choice.get("delta") else {
                    continue;
                };
                if ["reasoning", "reasoning_content"]
                    .iter()
                    .any(|key| nonempty(delta.get(key)))
                {
                    self.reasoning_seen = true;
                    // Usage may have arrived earlier; absent an explicit split it
                    // cannot safely describe useful output after reasoning begins.
                    self.useful_tokens = None;
                }
                let tool = delta
                    .get("tool_calls")
                    .and_then(Value::as_array)
                    .is_some_and(|calls| {
                        calls.iter().any(|call| {
                            call.get("function").is_some_and(|function| {
                                nonempty(function.get("name"))
                                    || nonempty(function.get("arguments"))
                            })
                        })
                    });
                if useful_content(delta.get("content")) || tool {
                    self.first.get_or_insert(elapsed);
                    self.last = Some(elapsed);
                }
            }
        }
        if let Some(usage) = json.get("usage") {
            let completion = usage.get("completion_tokens").and_then(Value::as_u64);
            let reasoning = usage
                .pointer("/completion_tokens_details/reasoning_tokens")
                .and_then(Value::as_u64);
            // Without an explicit reasoning split, provider usage semantics are
            // unverified. TTFT remains useful even when TPS is unavailable.
            self.useful_tokens = completion
                .zip(reasoning)
                .and_then(|(total, reasoning)| total.checked_sub(reasoning));
        }
    }
}

fn useful_content(value: Option<&Value>) -> bool {
    nonempty(value)
        || value.and_then(Value::as_array).is_some_and(|parts| {
            parts.iter().any(|part| {
                part.get("type").and_then(Value::as_str) == Some("text")
                    && nonempty(part.get("text"))
            })
        })
}

fn nonempty(value: Option<&Value>) -> bool {
    value
        .and_then(Value::as_str)
        .is_some_and(|text| !text.is_empty())
}

/// Validate a buffered completion without inventing stream timing.
pub fn buffered_outcome(bytes: &[u8]) -> Outcome {
    let failed = serde_json::from_slice::<Value>(bytes)
        .ok()
        .is_none_or(|json| {
            json.get("error").is_some_and(|error| !error.is_null())
                || !json
                    .get("choices")
                    .and_then(Value::as_array)
                    .is_some_and(|choices| {
                        !choices.is_empty()
                            && choices.iter().all(|choice| {
                                choice.get("message").is_some_and(|message| {
                                    message.get("content").is_some_and(Value::is_string)
                                        || message.get("refusal").is_some_and(Value::is_string)
                                        || message
                                            .get("tool_calls")
                                            .and_then(Value::as_array)
                                            .is_some_and(|calls| !calls.is_empty())
                                })
                            })
                    })
        });
    if failed {
        Outcome::UpstreamFailure
    } else {
        Outcome::Success
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn event(measurement: &mut StreamMeasurement, json: Value, seconds: u64) {
        let bytes = format!("data: {json}\n\n");
        // Exercise arbitrary network chunk boundaries.
        for part in bytes.as_bytes().chunks(3) {
            measurement.observe(part, Duration::from_secs(seconds));
        }
    }

    fn finish(measurement: StreamMeasurement) -> Observation {
        measurement.finish(
            "model".into(),
            Source::Traffic,
            10_000,
            Duration::from_secs(10),
        )
    }

    #[test]
    fn thinking_does_not_stop_ttft_and_is_excluded_from_tps() {
        let mut m = StreamMeasurement::default();
        event(
            &mut m,
            serde_json::json!({"choices":[{"delta":{"reasoning_content":"thinking"}}]}),
            1,
        );
        event(
            &mut m,
            serde_json::json!({"choices":[{"delta":{"content":"answer"}}]}),
            5,
        );
        event(
            &mut m,
            serde_json::json!({"choices":[{"delta":{"content":"more"}}]}),
            7,
        );
        event(
            &mut m,
            serde_json::json!({"choices":[], "usage":{"completion_tokens":1008,"completion_tokens_details":{"reasoning_tokens":1000}}}),
            8,
        );
        m.observe(b"data: [DONE]\n", Duration::from_secs(9));
        let observation = finish(m);
        assert_eq!(observation.ttft_ms, Some(5000.0));
        assert_eq!(observation.tps, Some(4.0));
        assert_eq!(observation.outcome, Outcome::Success);
    }

    #[test]
    fn typed_content_excludes_thinking_and_measures_text() {
        let mut m = StreamMeasurement::default();
        event(
            &mut m,
            serde_json::json!({"choices":[{"delta":{"content":[{"type":"thinking","thinking":[{"type":"text","text":"private"}]}]}}]}),
            1,
        );
        event(
            &mut m,
            serde_json::json!({"choices":[{"delta":{"content":[{"type":"text","text":"answer"}]}}]}),
            5,
        );
        event(
            &mut m,
            serde_json::json!({"choices":[{"delta":{"content":[{"type":"text","text":"more"}]}}]}),
            7,
        );
        event(
            &mut m,
            serde_json::json!({"choices":[],"usage":{"completion_tokens":108,"completion_tokens_details":{"reasoning_tokens":100}}}),
            8,
        );
        m.observe(b"data: [DONE]\n", Duration::from_secs(9));
        let result = finish(m);
        assert_eq!(result.ttft_ms, Some(5000.0));
        assert_eq!(result.tps, Some(4.0));
    }

    #[test]
    fn tool_calls_count_but_role_only_events_do_not() {
        let mut m = StreamMeasurement::default();
        event(
            &mut m,
            serde_json::json!({"choices":[{"delta":{"role":"assistant"}}]}),
            1,
        );
        event(
            &mut m,
            serde_json::json!({"choices":[{"delta":{"tool_calls":[{"function":{"name":"search"}}]},"finish_reason":"tool_calls"}]}),
            3,
        );
        assert_eq!(finish(m).ttft_ms, Some(3000.0));
    }

    #[test]
    fn missing_reasoning_split_omits_tps() {
        let mut m = StreamMeasurement::default();
        event(
            &mut m,
            serde_json::json!({"choices":[{"delta":{"content":"answer"},"finish_reason":"stop"}],"usage":{"completion_tokens":100}}),
            1,
        );
        assert_eq!(finish(m).tps, None);
    }

    #[test]
    fn provider_error_and_truncated_stream_are_failures() {
        let mut m = StreamMeasurement::default();
        event(
            &mut m,
            serde_json::json!({"error":{"message":"private error"}}),
            1,
        );
        m.observe(b"data: [DONE]\n", Duration::from_secs(2));
        assert_eq!(finish(m).outcome, Outcome::UpstreamFailure);
        assert_eq!(
            finish(StreamMeasurement::default()).outcome,
            Outcome::UpstreamFailure
        );
    }

    #[test]
    fn finishing_one_choice_does_not_complete_a_truncated_stream() {
        let mut m = StreamMeasurement::default();
        event(
            &mut m,
            serde_json::json!({"choices":[
                {"index":0,"delta":{"content":"a"},"finish_reason":"stop"},
                {"index":1,"delta":{"content":"b"},"finish_reason":null}
            ]}),
            1,
        );
        assert_eq!(finish(m).outcome, Outcome::UpstreamFailure);
    }

    #[test]
    fn backpressure_before_useful_output_omits_first_token_latency() {
        let mut measurement = StreamMeasurement::default();
        measurement.mark_backpressure();
        event(
            &mut measurement,
            serde_json::json!({"choices":[{"delta":{"content":"answer"}}]}),
            10,
        );
        measurement.observe(b"data: [DONE]\n", Duration::from_secs(11));
        let observation = finish(measurement);
        assert_eq!(observation.outcome, Outcome::Success);
        assert!(observation.ttft_ms.is_none());
        assert!(observation.tps.is_none());
    }

    #[test]
    fn backpressure_and_short_output_omit_tps() {
        for (tokens, backpressure) in [(3, false), (10, true)] {
            let mut m = StreamMeasurement::default();
            event(
                &mut m,
                serde_json::json!({"choices":[{"delta":{"content":"a"}}]}),
                1,
            );
            event(
                &mut m,
                serde_json::json!({"choices":[{"delta":{"content":"b"},"finish_reason":"stop"}],"usage":{"completion_tokens":tokens,"completion_tokens_details":{"reasoning_tokens":0}}}),
                2,
            );
            if backpressure {
                m.mark_backpressure();
            }
            m.observe(b"data: [DONE]\n", Duration::from_secs(3));
            let observation = finish(m);
            assert_eq!(observation.outcome, Outcome::Success);
            assert_eq!(observation.tps, None);
        }
    }
}
