use crate::inference::streaming::{EventParser, ParsedEvents};
use serde_json::Value;
mod finish;
mod tool_calls;
mod wire;

use super::{adapters::Adapter, reasoning::ReasoningCapture, types::*};
use std::collections::{BTreeMap, HashMap};
use wire::{CompletionChunk, project_content};

pub(super) struct StreamParser {
    output: ParsedEvents,
    adapter: Adapter,
    text_only: bool,
    calls: BTreeMap<i64, InferenceToolCall>,
    next_index: i64,
    metadata: HashMap<String, String>,
    reasoning: Option<ReasoningCapture>,
    bytes_seen: usize,
}

impl StreamParser {
    pub fn new(adapter: Adapter, input: &InferenceCompletionInput) -> Self {
        let reasoning =
            if !input.text_only && matches!(adapter, Adapter::Mistral { reasoning: true }) {
                input.reasoning_origin.clone().map(ReasoningCapture::new)
            } else {
                None
            };
        Self {
            output: ParsedEvents::default(),
            adapter,
            text_only: input.text_only,
            calls: BTreeMap::new(),
            next_index: 1000,
            metadata: HashMap::new(),
            reasoning,
            bytes_seen: 0,
        }
    }

    pub fn line(&mut self, line: &[u8]) {
        if self.output.done || self.output.error.is_some() {
            return;
        }
        let Some(payload) = line.strip_prefix(b"data:") else {
            return;
        };
        let payload = payload.strip_prefix(b" ").unwrap_or(payload);
        if payload == b"[DONE]" {
            self.eof();
            return;
        }
        self.bytes_seen += payload.len();
        if self.bytes_seen > 16 * 1024 * 1024 {
            self.output.error = Some(InferenceError::LimitExceeded {
                limit: "16 MiB stream data".into(),
            });
            return;
        }
        if let Err(error) = self.chunk(payload) {
            self.output.error = Some(if self.output.refused {
                InferenceError::PolicyStop
            } else {
                error
            });
        }
    }

    fn chunk(&mut self, payload: &[u8]) -> Result<(), InferenceError> {
        let decoded = serde_json::from_slice::<CompletionChunk>(payload);
        if (decoded.is_err() || self.text_only)
            && let Ok(value) = serde_json::from_slice::<Value>(payload)
            && let (Some(message), Some(_)) = (
                value["error"]["message"].as_str(),
                value["error"]["type"].as_str(),
            )
        {
            return Err(InferenceError::Http {
                status: 0,
                body: Some(message.into()),
            });
        }
        let chunk = match decoded {
            Ok(chunk) => chunk,
            Err(error) => {
                if let Some(reasoning) = &mut self.reasoning {
                    reasoning.invalidate();
                }
                return if self.text_only {
                    Err(error.into())
                } else {
                    Ok(())
                };
            }
        };
        let Some(choice) = chunk.choices.first() else {
            return Ok(());
        };
        let visible = match project_content(choice.delta.content.as_ref()) {
            Ok(visible) => visible,
            Err(error) => {
                if let Some(reasoning) = &mut self.reasoning {
                    reasoning.invalidate();
                }
                return if self.text_only { Err(error) } else { Ok(()) };
            }
        };
        if self.text_only {
            if let Some(text) = visible {
                self.output
                    .events
                    .push_back(InferenceEvent::ContentDelta { text });
            }
            return Ok(());
        }
        if let Some(refusal) = &choice.delta.refusal
            && !refusal.is_empty()
        {
            self.output.events.push_back(InferenceEvent::ContentDelta {
                text: refusal.clone(),
            });
            self.output.refused = true;
        }
        if let (Some(reasoning), Some(content)) = (&mut self.reasoning, &choice.delta.content) {
            reasoning.append(content);
        }
        if let Some(text) = visible {
            self.output
                .events
                .push_back(InferenceEvent::ContentDelta { text });
        }
        if let Some(calls) = &choice.delta.tool_calls {
            for delta in calls {
                self.tool(delta);
            }
        }
        if let Some(reason) = &choice.finish_reason {
            self.finish(reason)?;
        }
        Ok(())
    }

    pub fn eof(&mut self) {
        if self.output.done || self.output.error.is_some() {
            return;
        }
        if self.text_only {
            self.output.done = true;
        } else {
            self.output.error = Some(if self.output.refused {
                InferenceError::PolicyStop
            } else {
                InferenceError::Interrupted
            });
        }
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
