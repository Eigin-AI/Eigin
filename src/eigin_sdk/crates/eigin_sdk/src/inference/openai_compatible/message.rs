use super::{adapters::Adapter, types::*};
use base64::{Engine, engine::general_purpose::STANDARD};
use serde_json::{Value, json};

impl Adapter {
    pub(super) fn encode_message(
        self,
        message: &InferenceMessage,
        origin: Option<&InferenceReasoningOrigin>,
    ) -> Value {
        let mut wire = json!({"role":message.role});
        if let Some(text) = &message.content {
            wire["content"] = json!(text);
        }
        if message.has_attachments || !message.images.is_empty() {
            let mut parts = Vec::new();
            if let Some(text) = &message.content
                && !text.is_empty()
            {
                parts.push(json!({"type":"text","text":text}));
            }
            for image in &message.images {
                parts.push(json!({
                    "type": "image_url",
                    "image_url": {
                        "url": format!("data:{};base64,{}", image.mime_type, STANDARD.encode(&image.bytes)),
                        "detail": "high"
                    }
                }));
            }
            if !parts.is_empty() {
                wire["content"] = json!(parts);
            }
        }

        if let Some(name) = &message.name {
            wire["name"] = json!(name);
        }
        if let Some(id) = &message.tool_call_id {
            wire["tool_call_id"] = json!(self.tool_id(id));
        }

        if let Some(calls) = &message.tool_calls {
            let mut calls: Vec<_> = calls
                .iter()
                .map(|call| self.encode_tool_call(call))
                .collect();
            if matches!(self, Self::Gemini)
                && !calls.is_empty()
                && let Some(signature) = message.provider_metadata.get("thought_signature")
            {
                calls[0]["extra_content"] = json!({"google":{"thought_signature":signature}});
            }
            wire["tool_calls"] = json!(calls);
        }

        if matches!(self, Self::Mistral { reasoning: true })
            && let Some(history) = &message.reasoning_history
            && history.format == super::reasoning::MISTRAL_REASONING_FORMAT
            && Some(&history.origin) == origin
            && message.role == "assistant"
            && history.visible_text == message.content.as_deref().unwrap_or("")
            && let Ok(parts) = serde_json::from_slice::<Vec<super::reasoning::MistralReasoningPart>>(
                &history.payload,
            )
            && let Ok(parts) = serde_json::to_value(parts)
        {
            wire["content"] = parts;
        }
        wire
    }

    fn encode_tool_call(self, call: &InferenceToolCall) -> Value {
        json!({
            "id": self.tool_id(&call.id),
            "type": call.kind,
            "function": { "name": call.name, "arguments": call.arguments }
        })
    }

    fn tool_id(self, id: &str) -> String {
        if !matches!(self, Self::Mistral { .. }) {
            return id.into();
        }
        let chars: Vec<_> = id.chars().filter(|c| c.is_alphanumeric()).collect();
        chars[chars.len().saturating_sub(9)..].iter().collect()
    }
}
