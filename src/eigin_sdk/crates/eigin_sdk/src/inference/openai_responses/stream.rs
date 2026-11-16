use super::super::types::*;
use crate::inference::streaming::{EventParser, ParsedEvents};

#[derive(Default)]
pub(super) struct StreamParser {
    output: ParsedEvents,
    has_tools: bool,
    streamed_tools: std::collections::HashSet<Option<String>>,
    performance: crate::inference::streaming::Performance,
}

impl StreamParser {
    pub fn line(&mut self, line: &[u8]) {
        if self.output.done || self.output.error.is_some() {
            return;
        }
        let Some(payload) = line.strip_prefix(b"data: ") else {
            return;
        };
        if payload == b"[DONE]" {
            self.eof();
            return;
        }
        let Ok(event) = serde_json::from_slice::<super::event::Event>(payload) else {
            return;
        };
        match event.r#type.as_deref().unwrap_or("") {
            "response.refusal.delta" => {
                self.output.refused = true;
                if let Some(text) = event.delta.as_deref() {
                    self.text(text);
                }
            }
            "response.refusal.done" => {
                self.output.refused = true;
                self.output.error = Some(InferenceError::PolicyStop);
            }
            "response.output_text.delta" => {
                if let Some(text) = event.delta.as_deref().filter(|s| !s.is_empty()) {
                    self.performance.useful_output();
                    self.text(text);
                }
            }
            "response.output_item.added" => {
                if let Some(item) = event
                    .item
                    .filter(|item| item.r#type.as_deref() == Some("function_call"))
                    && item.name.as_ref().is_some_and(|name| !name.is_empty())
                {
                    self.streamed_tools.insert(item.id);
                    self.performance.useful_output();
                }
            }
            "response.function_call_arguments.delta" => {
                if event.delta.as_ref().is_some_and(|delta| !delta.is_empty()) {
                    self.streamed_tools.insert(event.item_id);
                    self.performance.useful_output();
                }
            }
            "response.output_item.done" => {
                let Some(item) = event
                    .item
                    .filter(|item| item.r#type.as_deref() == Some("function_call"))
                else {
                    return;
                };
                if !self.streamed_tools.remove(&item.id)
                    && [item.name.as_deref(), item.arguments.as_deref()]
                        .into_iter()
                        .flatten()
                        .any(|value| !value.is_empty())
                {
                    self.performance.useful_output();
                }
                self.has_tools = true;
                self.output.events.push_back(InferenceEvent::ToolCall {
                    call: InferenceToolCall {
                        id: item
                            .call_id
                            .unwrap_or_else(|| uuid::Uuid::new_v4().to_string().to_uppercase()),
                        kind: "function".into(),
                        name: item.name.unwrap_or_default(),
                        arguments: item.arguments.unwrap_or_default(),
                    },
                });
            }
            "response.completed" => {
                if self.output.refused {
                    self.output.error = Some(InferenceError::PolicyStop);
                } else {
                    if let Some(usage) = event.response.and_then(|response| response.usage) {
                        self.performance.tokens(
                            usage
                                .get("output_tokens")
                                .and_then(serde_json::Value::as_u64),
                            usage
                                .pointer("/output_tokens_details/reasoning_tokens")
                                .and_then(serde_json::Value::as_u64),
                        );
                    }
                    self.output.events.push_back(self.performance.event());
                    self.output.events.push_back(InferenceEvent::Finished {
                        reason: if self.has_tools {
                            InferenceFinishReason::ToolCalls
                        } else {
                            InferenceFinishReason::Stop
                        },
                    });
                    self.output.done = true;
                }
            }
            "response.incomplete" => {
                self.output.error = Some(
                    if event
                        .response
                        .as_ref()
                        .and_then(|response| response.incomplete_details.as_ref())
                        .and_then(|details| details.reason.as_deref())
                        == Some("content_filter")
                    {
                        InferenceError::PolicyStop
                    } else {
                        InferenceError::OutputLimit
                    },
                );
            }
            "response.failed" | "error" => {
                self.output.error = Some(super::error::event_error(&event))
            }
            _ => {}
        }
        if self.output.refused && self.output.error.is_some() {
            self.output.error = Some(InferenceError::PolicyStop);
        }
    }

    pub fn eof(&mut self) {
        if !self.output.done && self.output.error.is_none() {
            self.output.error = Some(if self.output.refused {
                InferenceError::PolicyStop
            } else {
                InferenceError::Interrupted
            });
        }
        self.output.done = true;
    }

    fn text(&mut self, text: &str) {
        self.output
            .events
            .push_back(InferenceEvent::ContentDelta { text: text.into() });
    }
}

impl EventParser for StreamParser {
    fn start(&mut self) {
        self.performance.start();
    }
    fn received_chunk(&mut self) {
        self.performance.received_chunk();
    }

    fn output(&self) -> &ParsedEvents {
        &self.output
    }
    fn output_mut(&mut self) -> &mut ParsedEvents {
        &mut self.output
    }
    fn line(&mut self, line: &[u8]) {
        self.line(line);
    }
    fn eof(&mut self) {
        self.eof();
    }
}
