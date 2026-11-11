use super::types::*;
use serde::{Deserialize, Serialize};
use serde_json::Value;

/// Mistral is the only reasoning replay format this provider supports.
pub(super) const MISTRAL_REASONING_FORMAT: &str = "mistral-content-v1";

#[derive(Clone, Debug, Serialize, Deserialize)]
pub(super) struct MistralReasoningPart {
    #[serde(rename = "type")]
    kind: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    text: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    thinking: Option<Vec<MistralReasoningPart>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    closed: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    signature: Option<String>,
}

pub(super) struct ReasoningCapture {
    origin: InferenceReasoningOrigin,
    parts: Vec<MistralReasoningPart>,
    valid: bool,
}

impl ReasoningCapture {
    pub fn new(origin: InferenceReasoningOrigin) -> Self {
        Self {
            origin,
            parts: vec![],
            valid: true,
        }
    }

    pub fn invalidate(&mut self) {
        self.valid = false;
    }

    pub fn append(&mut self, content: &Value) {
        if content.is_null() {
            return;
        }
        let plain = content.is_string();
        let incoming = if let Some(text) = content.as_str() {
            vec![MistralReasoningPart {
                kind: "text".into(),
                text: Some(text.into()),
                thinking: None,
                closed: None,
                signature: None,
            }]
        } else {
            match serde_json::from_value::<Vec<MistralReasoningPart>>(content.clone()) {
                Ok(parts) => parts,
                Err(_) => {
                    self.invalidate();
                    return;
                }
            }
        };
        for part in incoming {
            if part.kind != "text" && part.kind != "thinking" {
                self.invalidate();
                continue;
            }
            if part.kind == "thinking"
                && part
                    .thinking
                    .as_ref()
                    .is_some_and(|v| v.iter().any(|p| p.kind != "text"))
            {
                self.invalidate();
            }
            if let Some(last) = self.parts.last_mut() {
                if last.kind == "thinking" && last.closed == Some(false) {
                    if part.kind != "thinking" {
                        self.invalidate();
                        continue;
                    }
                    last.thinking
                        .get_or_insert_default()
                        .extend(part.thinking.unwrap_or_default());
                    if part.closed.is_some() {
                        last.closed = part.closed;
                    }
                    if let Some(signature) = part.signature {
                        if last.signature.as_ref().is_some_and(|old| old != &signature) {
                            self.valid = false;
                        }
                        last.signature = Some(signature);
                    }
                    continue;
                }
                if plain && last.kind == "text" && part.kind == "text" {
                    last.text
                        .get_or_insert_default()
                        .push_str(part.text.as_deref().unwrap_or(""));
                    continue;
                }
            }
            self.parts.push(part);
        }
    }

    pub fn completed(&self) -> Option<InferenceReasoningHistory> {
        if !self.valid
            || !self.parts.iter().any(|p| p.kind == "thinking")
            || self.parts.iter().any(|p| p.closed == Some(false))
        {
            return None;
        }
        let thinking: String = self
            .parts
            .iter()
            .filter(|p| p.kind == "thinking")
            .flat_map(|p| p.thinking.iter().flatten())
            .filter_map(|p| p.text.as_deref())
            .collect();
        Some(InferenceReasoningHistory {
            origin: self.origin.clone(),
            format: MISTRAL_REASONING_FORMAT.into(),
            payload: serde_json::to_vec(&self.parts).ok()?,
            visible_text: self
                .parts
                .iter()
                .filter(|p| p.kind == "text")
                .filter_map(|p| p.text.as_deref())
                .collect(),
            additional_input_tokens: crate::context::estimate_text(thinking)
                + self.parts.len() as i64 * 4,
        })
    }
}
