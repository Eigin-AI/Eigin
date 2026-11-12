use super::super::types::*;
use super::events::*;
use crate::inference::streaming::{EventParser, ParsedEvents};
use std::collections::HashMap;

#[derive(Default)]
pub(super) struct StreamParser {
    output: ParsedEvents,
    event: Option<String>,
    tools: HashMap<i64, InferenceToolCall>,
    finish: Option<InferenceFinishReason>,
}

impl EventParser for StreamParser {
    fn output(&self) -> &ParsedEvents {
        &self.output
    }

    fn output_mut(&mut self) -> &mut ParsedEvents {
        &mut self.output
    }

    fn line(&mut self, line: &[u8]) {
        if self.output.done || self.output.error.is_some() {
            return;
        }

        if let Some(event) = line.strip_prefix(b"event: ") {
            self.event = std::str::from_utf8(event).ok().map(str::to_owned);
            return;
        }
        let Some(payload) = line.strip_prefix(b"data: ") else {
            return;
        };
        let Some(event) = self.event.as_deref() else {
            return;
        };

        match event {
            "content_block_start" => {
                let Ok(start) = serde_json::from_slice::<BlockStart>(payload) else {
                    return;
                };
                if start.content_block.r#type == "tool_use"
                    && let (Some(id), Some(name)) =
                        (start.content_block.id, start.content_block.name)
                {
                    self.tools.insert(
                        start.index,
                        InferenceToolCall {
                            id,
                            name,
                            kind: "function".into(),
                            arguments: String::new(),
                        },
                    );
                }
            }
            "content_block_delta" => {
                let Ok(delta) = serde_json::from_slice::<BlockDelta>(payload) else {
                    return;
                };
                match delta.delta.r#type.as_str() {
                    "text_delta" => {
                        if let Some(text) = delta.delta.text {
                            self.output
                                .events
                                .push_back(InferenceEvent::ContentDelta { text });
                        }
                    }
                    "input_json_delta" => {
                        if let (Some(tool), Some(partial)) =
                            (self.tools.get_mut(&delta.index), delta.delta.partial_json)
                        {
                            tool.arguments.push_str(&partial);
                        }
                    }
                    _ => {}
                }
            }
            "content_block_stop" => {
                if let Ok(stop) = serde_json::from_slice::<BlockStop>(payload)
                    && let Some(call) = self.tools.remove(&stop.index)
                {
                    self.output
                        .events
                        .push_back(InferenceEvent::ToolCall { call });
                }
            }
            "message_delta" => {
                let Ok(delta) = serde_json::from_slice::<MessageDelta>(payload) else {
                    return;
                };
                if let Some(reason) = delta.delta.stop_reason {
                    match reason.as_str() {
                        "tool_use" => self.finish = Some(InferenceFinishReason::ToolCalls),
                        "end_turn" | "stop_sequence" => {
                            self.finish = Some(InferenceFinishReason::Stop)
                        }
                        "max_tokens" => self.output.error = Some(InferenceError::OutputLimit),
                        _ => self.output.error = Some(InferenceError::PolicyStop),
                    }
                }
            }
            "message_stop" => {
                if let Some(reason) = self.finish.clone().filter(|_| self.tools.is_empty()) {
                    self.output
                        .events
                        .push_back(InferenceEvent::Finished { reason });
                    self.output.done = true;
                } else {
                    self.output.error = Some(InferenceError::Interrupted);
                }
            }
            "error" => {
                if let Ok(error) = serde_json::from_slice::<StreamError>(payload) {
                    self.output.error = Some(InferenceError::Http {
                        status: 500,
                        body: Some(format!("{}: {}", error.error.r#type, error.error.message)),
                    });
                }
            }
            _ => {}
        }

        self.event = None;
    }

    fn eof(&mut self) {
        if !self.output.done && self.output.error.is_none() {
            self.output.error = Some(InferenceError::Interrupted);
        }
        self.output.done = true;
    }
}
