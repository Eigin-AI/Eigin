use super::super::types::*;
use crate::inference::streaming::{EventParser, ParsedEvents};

#[derive(Default)]
pub(super) struct StreamParser {
    output: ParsedEvents,
    has_tools: bool,
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
                    self.text(text);
                }
            }
            "response.output_item.done" => {
                let Some(item) = event
                    .item
                    .filter(|item| item.r#type.as_deref() == Some("function_call"))
                else {
                    return;
                };
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
